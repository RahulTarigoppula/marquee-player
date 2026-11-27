# Installs the freshly built Setup on the CI runner, starts the installed app, installs again
# OVER the running app (the upgrade a friend does), starts it once more and uninstalls it.
# Nobody can run the installer on the dev machine, so this is the only place its upgrade and
# uninstall paths are ever exercised. Called by release.yml; advisory there (a red result is
# reported in the run summary but does not hold the build back).
#
#   pwsh scripts/installer-smoke.ps1 -Installer out\marquee-windows-x64-setup.exe -LogDir logs
#
# Per-user and silent: it writes to %LOCALAPPDATA%\Programs\Marquee and HKCU only, and removes
# both again. Do not run it on a PC whose own Marquee install you want to keep.
param(
  [Parameter(Mandatory = $true)][string]$Installer,
  [string]$LogDir = 'installer-smoke'
)

$ErrorActionPreference = 'Stop'
$Installer = (Resolve-Path $Installer).Path
New-Item -ItemType Directory -Force $LogDir | Out-Null
$LogDir = (Resolve-Path $LogDir).Path

$app = Join-Path $env:LOCALAPPDATA 'Programs\Marquee'
$exe = Join-Path $app 'marquee.exe'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{6A8F3C2E-4B1D-4E7A-9C5F-2D8B1E0A7F43}_is1'
$classes = 'HKCU:\Software\Classes'
$failures = New-Object System.Collections.Generic.List[string]

function Test-Step([string]$What, [bool]$Ok) {
  if ($Ok) {
    Write-Host "ok    $What"
  } else {
    Write-Host "FAIL  $What"
    Write-Host "::error title=Installer smoke test::$What"
    $script:failures.Add($What)
  }
}

function Invoke-Setup([string]$Tag) {
  $log = Join-Path $LogDir "setup-$Tag.log"
  $p = Start-Process -FilePath $Installer -PassThru -Wait -ArgumentList @(
    '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CURRENTUSER', "/LOG=`"$log`""
  )
  return $p.ExitCode
}

function Start-Marquee {
  # Not the child of this script's console: a GUI app started the way Explorer starts it.
  $p = Start-Process -FilePath $exe -PassThru
  $shown = $false
  for ($i = 0; $i -lt 60 -and -not $p.HasExited; $i++) {
    Start-Sleep -Milliseconds 500
    $p.Refresh()
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $shown = $true; break }
  }
  # Still there ten seconds later: no crash on start-up, with or without a window handle.
  Start-Sleep -Seconds 10
  $p.Refresh()
  return [pscustomobject]@{ Process = $p; Shown = $shown; Alive = (-not $p.HasExited) }
}

# Where the running app keeps its database: %APPDATA%\<company>\<product>\marquee.sqlite.
function Find-Database {
  $hit = Get-ChildItem -LiteralPath $env:APPDATA -Recurse -Depth 3 -Filter 'marquee.sqlite' -File -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -eq $hit) { return $null }
  return $hit.FullName
}

function Wait-Gone([string]$Path, [int]$Seconds = 30) {
  for ($i = 0; $i -lt ($Seconds * 2) -and (Test-Path $Path); $i++) { Start-Sleep -Milliseconds 500 }
  return -not (Test-Path $Path)
}

function Get-Default([string]$Key) {
  if (-not (Test-Path -LiteralPath $Key)) { return $null }
  return (Get-Item -LiteralPath $Key).GetValue('')
}

try {
  if (Test-Path $app) {
    Write-Host "::warning::installer smoke: $app already exists on this machine; results may mislead"
  }

  # ── 1. fresh install ──
  $code = Invoke-Setup 'fresh'
  Test-Step "fresh install exits 0 (was $code)" ($code -eq 0)
  foreach ($f in 'marquee.exe', 'libmpv-2.dll', 'flutter_windows.dll', 'vcruntime140.dll', 'msvcp140.dll', 'data\app.so', 'data\icudtl.dat') {
    Test-Step "installed: $f" (Test-Path (Join-Path $app $f))
  }
  Test-Step 'an uninstaller was written' ($null -ne (Get-ChildItem $app -Filter 'unins*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1))
  Test-Step 'Apps list entry (HKCU uninstall key)' (Test-Path -LiteralPath $uninstallKey)
  $open = Get-Default "$classes\Marquee.Video\shell\open\command"
  Test-Step "Marquee.Video opens with the installed exe ($open)" ("$open" -like "*$exe*")
  $progids = Get-Item -LiteralPath "$classes\.mkv\OpenWithProgids" -ErrorAction SilentlyContinue
  Test-Step '.mkv lists Marquee under "Open with"' ($null -ne $progids -and ($progids.GetValueNames() -contains 'Marquee.Video'))
  Test-Step '.mkv default app is untouched' ([string]::IsNullOrEmpty((Get-Default "$classes\.mkv")))
  $verb = Get-Default "$classes\SystemFileAssociations\video\shell\Marquee"
  Test-Step "right-click verb reads 'Open with Marquee' ($verb)" ($verb -eq 'Open with Marquee')

  # ── 2. the installed app starts ──
  if (Test-Path $exe) {
    $first = Start-Marquee
    Test-Step 'the installed app opened a window' $first.Shown
    Test-Step 'the installed app is still running after 10 s' $first.Alive
    # The database belongs in the app's own data folder, never in Documents (often OneDrive).
    $docDb = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'marquee.sqlite'
    $db = Find-Database
    Test-Step "the database was created under %APPDATA% ($db)" ($null -ne $db)
    Test-Step 'no database in Documents' (-not (Test-Path -LiteralPath $docDb))

    # ── 3. upgrade in place, over the running app ──
    $code = Invoke-Setup 'upgrade'
    Test-Step "install over the running app exits 0 (was $code)" ($code -eq 0)
    $first.Process.Refresh()
    Test-Step 'Setup closed the running app before replacing its files' $first.Process.HasExited
    Test-Step 'marquee.exe is in place after the upgrade' (Test-Path $exe)
    $entries = @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
        Where-Object { $_.GetValue('DisplayName') -eq 'Marquee' })
    Test-Step "one Apps list entry after the upgrade (found $($entries.Count))" ($entries.Count -eq 1)

    # ── 3b. a database left in Documents by an older version is moved, not lost ──
    # Put the one just created back where 2.1 kept it: the next start has to carry it over.
    $moved = $false
    if ($null -ne $db -and (Test-Path -LiteralPath $db)) {
      $size = (Get-Item -LiteralPath $db).Length
      Move-Item -LiteralPath $db -Destination $docDb -Force
      foreach ($side in '-wal', '-shm', '-journal') {
        Remove-Item -LiteralPath "$db$side" -Force -ErrorAction SilentlyContinue
      }
      $moved = $true
    }

    # ── 4. uninstall, again with the app running ──
    $second = Start-Marquee
    Test-Step 'the upgraded app is running' $second.Alive
    if ($moved) {
      $after = Find-Database
      Test-Step "the old database was carried over to %APPDATA% ($after)" ($null -ne $after)
      Test-Step 'and it is no longer in Documents' (-not (Test-Path -LiteralPath $docDb))
      if ($null -ne $after) {
        $now = (Get-Item -LiteralPath $after).Length
        Test-Step "nothing was cut off on the way ($size bytes before, $now after)" ($now -ge $size)
      }
    }
    $unins = Get-ChildItem $app -Filter 'unins*.exe' | Select-Object -First 1
    $ulog = Join-Path $LogDir 'uninstall.log'
    Start-Process -FilePath $unins.FullName -Wait -ArgumentList @(
      '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$ulog`""
    )
    # The uninstaller re-launches itself from %TEMP%: give the copy time to finish.
    $gone = Wait-Gone $app 45
    $second.Process.Refresh()
    Test-Step 'the uninstaller closed the running app' $second.Process.HasExited
    if (-not $gone) {
      Write-Host 'left behind:'
      Get-ChildItem $app -Recurse -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.FullName)" }
    }
    Test-Step 'the install folder is gone' $gone
    Test-Step 'the Apps list entry is gone' (-not (Test-Path -LiteralPath $uninstallKey))
    Test-Step 'Marquee.Video is gone from HKCU' (-not (Test-Path -LiteralPath "$classes\Marquee.Video"))
    Test-Step 'Applications\marquee.exe is gone' (-not (Test-Path -LiteralPath "$classes\Applications\marquee.exe"))
    Test-Step 'the right-click verb is gone' (-not (Test-Path -LiteralPath "$classes\SystemFileAssociations\video\shell\Marquee"))
    Test-Step 'HKCU\Software\Marquee is gone' (-not (Test-Path -LiteralPath 'HKCU:\Software\Marquee'))
    $after = Get-Item -LiteralPath "$classes\.mkv\OpenWithProgids" -ErrorAction SilentlyContinue
    Test-Step '.mkv no longer lists Marquee' ($null -eq $after -or -not ($after.GetValueNames() -contains 'Marquee.Video'))
  }
} catch {
  Test-Step "the smoke test itself broke: $($_.Exception.Message)" $false
} finally {
  # Leave nothing running on the runner whatever happened.
  Get-Process -Name 'marquee' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($failures.Count -gt 0) {
  Write-Host "installer smoke: $($failures.Count) check(s) failed; Setup logs are in $LogDir"
  if ($env:GITHUB_STEP_SUMMARY) {
    $lines = @('### Installer smoke test: FAILED (advisory)', '') + ($failures | ForEach-Object { "- $_" })
    $lines | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
  }
  exit 1
}
Write-Host 'installer smoke: install, launch, upgrade over the running app and uninstall all passed'
if ($env:GITHUB_STEP_SUMMARY) {
  '### Installer smoke test: passed', '', 'Fresh install, launch, install over the running app, uninstall: all clean.' |
    Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Append -Encoding utf8
}
exit 0
