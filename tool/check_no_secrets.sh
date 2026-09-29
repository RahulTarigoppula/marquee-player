#!/usr/bin/env bash
# G5/G6 — no secrets, no telemetry (IMPLEMENTATION-PROMPT §2.5, §10.7).
#
#   1. No telemetry SDK anywhere in code or config: analytics|sentry|posthog|gtag|firebase.
#      Prose (*.md, docs/), lockfiles, node_modules and the worker's own "must not have analytics"
#      tests are out of scope; TOML/YAML comments are ignored.
#   2. No signing material or local machine config is tracked: *.p12, *.jks, *.keystore,
#      key.properties, local.properties.
#   3. The built Lite bundle (web/dist, when present) carries no API key: no VITE_*KEY name, no
#      Api-Key header with a 32-char literal, and not the value of $OS_API_KEY if it is set.
#
# Usage: bash tool/check_no_secrets.sh   (from anywhere; exits 1 on any finding)
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 2
fail=0
say() { printf '%s\n' "$*"; }
bad() { printf '::error::%s\n' "$*"; fail=1; }

# Every file that is (or would be) in git, honouring .gitignore; plain find outside a work tree.
list_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -z --cached --others --exclude-standard
  else
    find . -type f \
      -not -path './.git/*' -not -path '*/node_modules/*' -not -path '*/.dart_tool/*' \
      -not -path './build/*' -not -path '*/dist/*' -not -path '*/.wrangler/*' -print0 |
      sed -z 's#^\./##'
  fi
}

tracked_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -z --cached
  else
    list_files
  fi
}

# ---------------------------------------------------------------- 1. telemetry
say '== telemetry grep (analytics|sentry|posthog|gtag|firebase)'
pattern='analytics|sentry|posthog|gtag|firebase'
hits=0
while IFS= read -r -d '' f; do
  case "$f" in
    docs/* | *.md | */node_modules/* | node_modules/* | */.dart_tool/* | build/* | web/dist/*) continue ;;
    package-lock.json | */package-lock.json | pubspec.lock | */pubspec.lock | *.lock) continue ;;
    tool/check_no_secrets.sh | worker/test/*) continue ;;
    *.png | *.jpg | *.jpeg | *.gif | *.webp | *.ico | *.ttf | *.otf | *.woff | *.woff2 | *.mkv | *.mp4 | *.webm | *.avi | *.p12 | *.jks) continue ;;
  esac
  [ -f "$f" ] || continue
  case "$f" in
    *.toml | *.yml | *.yaml) out=$(grep -n -i -E "$pattern" "$f" | grep -v -E '^[0-9]+:[[:space:]]*#' || true) ;;
    *) out=$(grep -n -i -E "$pattern" "$f" || true) ;;
  esac
  if [ -n "$out" ]; then
    while IFS= read -r line; do bad "telemetry reference in $f:$line"; done <<<"$out"
    hits=$((hits + 1))
  fi
done < <(list_files)
[ "$hits" -eq 0 ] && say '   ok'

# ---------------------------------------------------------------- 2. signing material
say '== tracked signing material / local config'
signing=0
while IFS= read -r -d '' f; do
  case "$f" in
    *.p12 | *.jks | *.keystore | key.properties | */key.properties | local.properties | */local.properties)
      bad "must never be tracked: $f"
      signing=1
      ;;
  esac
done < <(tracked_files)
[ "$signing" -eq 0 ] && say '   ok'

# ---------------------------------------------------------------- 3. the Lite bundle
say '== web/dist key scan'
if [ -d web/dist ]; then
  leak=0
  if grep -r -n -o -E 'VITE_[A-Z0-9_]*KEY' web/dist >/dev/null 2>&1; then
    grep -r -n -o -E 'VITE_[A-Z0-9_]*KEY' web/dist | head -5 | while IFS= read -r l; do printf '::error::VITE_*KEY in bundle: %s\n' "$l"; done
    leak=1
  fi
  if grep -r -n -i -o -E "api-key['\"]?[[:space:]]*[:,=][[:space:]]*['\"][A-Za-z0-9]{32}['\"]" web/dist >/dev/null 2>&1; then
    bad 'an Api-Key header with a 32-character literal is in web/dist'
    leak=1
  fi
  if [ -n "${OS_API_KEY:-}" ] && grep -r -q -F -- "$OS_API_KEY" web/dist; then
    bad 'the value of OS_API_KEY is in web/dist'
    leak=1
  fi
  [ "$leak" -eq 0 ] && say '   ok' || fail=1
else
  say '   skipped (no web/dist)'
fi

if [ "$fail" -ne 0 ]; then
  say 'check_no_secrets: FAILED'
  exit 1
fi
say 'check_no_secrets: clean'
