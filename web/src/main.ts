// Marquee Lite — wiring. One AppState, DOM updates by CSS custom properties and textContent,
// overlays toggled with `hidden` (and everything beneath the top layer made `inert`).
// With a Worker (VITE_API_BASE set) the ritual is:
//   drop → capability probe → moviehash → IndexedDB (a hit costs ZERO requests) → search →
//   score → auto-pick → download (signed in, via the Worker) → subtitle-file → SRT→VTT →
//   <track> via a Blob URL → play.
// Without one, a film goes straight to the picture; the moviehash still keys the local cache
// (a subtitle file you added before re-attaches), the sync offset and the resume point.
import './styles/tokens.css'
import './styles/app.css'
import './styles/player.css'
import { API_BASE, releasesUrl, SIGN_UP_URL, searchEnabled } from './config'
import { candidatesFromSearch, createApi, hashSearchParams, nameSearchParams } from './engine/api'
import { noPrintReason, type PrintSniff, probeCapability, sniffPrint } from './engine/capability'
import { parseName, parsePath } from './engine/filename'
import { defaultLanguage, languageLabel } from './engine/languages'
import { HashUnavailable, isFileTooSmall, osHash } from './engine/osHash'
import { rank } from './engine/scoring'
import { decodeSubtitle, parseSidecar, sidecarKind } from './engine/sidecar'
import { type Cue, parseSrt, toVtt } from './engine/srt2vtt'
import { OffsetBook, snap, reset as syncReset, step as syncStep } from './engine/syncRule'
import {
  type Effect,
  FAILURE_SENTENCE,
  initial,
  type Machine,
  reduce,
  type SearchRung,
  type ThreadingEvent,
} from './engine/threading'
import {
  ANONYMOUS,
  quotaFromDownload,
  quotaFromLogin,
  quotaFromUserInfo,
  ticketStrip as stripModel,
} from './engine/tickets'
import type {
  Capability,
  LiteSession,
  MovieHash,
  ParsedName,
  ScoredCandidate,
  ThreadingState,
} from './engine/types'
import * as idb from './storage/idb'
import { loadPrefs, savePrefs } from './storage/prefs'
import type { AssTrack } from './ui/ass'
import { auditorium } from './ui/auditorium'
import { type BoothTrack, booth, CUE_SCALE, type CueSize } from './ui/booth'
import { h } from './ui/dom'
import { leader } from './ui/leader'
import { liteLanding, skyFor } from './ui/lite'
import { noPrint } from './ui/noPrint'
import { signIn } from './ui/signIn'
import { ticketStrip } from './ui/ticketStrip'

const PLAYABLE_WITHIN_MS = 5000
const SNIFF_BYTES = 1 << 20
const RESYNC_DEBOUNCE_MS = 120
const SOUND_CHECK_MS = 2000
const RESUME_MIN_S = 30 // nearer the start than this, a film simply starts again
const RESUME_TAIL_S = 120 // within the last two minutes, the film counts as watched
const RESUME_SAVE_MS = 5000
const APP_TITLE = 'Marquee Lite'
const root = document.documentElement
const now = () => performance.now()

// ── state ──
const prefs = loadPrefs()
const language =
  prefs.language ?? defaultLanguage(navigator.languages?.length ? navigator.languages : ['en'])
const RELEASES = releasesUrl(location)
const APP_LINK = { href: RELEASES, label: 'Get the Windows / Android app' }

interface Subtitle {
  label: string
  status: BoothTrack['status']
  /** The OpenSubtitles file_id, so "Find another print" never offers it again. */
  fileId: string | null
}

const app = {
  session: {
    jwt: null,
    jwtExpiresAt: null,
    quota: ANONYMOUS,
    languages: [language],
    preferHearingImpaired: false,
  } as LiteSession,
  user: null as string | null,
  sessionOnly: false,
  machine: initial({ subdlEnabled: false, language }, ANONYMOUS) as Machine,
  sentence: null as string | null, // the Worker's own sentence for the current stall
  capability: null as Capability | null,
  file: null as File | null,
  parsed: null as ParsedName | null,
  hash: null as MovieHash | null,
  printOk: null as boolean | null,
  cues: null as Cue[] | null,
  ass: null as AssTrack | null,
  subtitle: null as Subtitle | null,
  /** A sidecar SRT/VTT waiting for the moviehash so it can be remembered for next time. */
  sidecarToCache: null as { cues: Cue[]; name: string } | null,
  subsOn: true,
  inSync: false,
  delay: 0,
  cueSize: prefs.cueSize as CueSize,
  pendingTear: false,
  controller: new AbortController(),
  trackUrl: null as string | null,
  videoUrl: null as string | null,
  noPrintEl: null as HTMLElement | null,
  resumeKey: null as string | null,
}
const offsets = new OffsetBook()
// With no Worker configured (VITE_API_BASE empty) nothing is ever fetched: the search UI is
// not shown at all, and this stub is only a safety net.
const notConfigured = (): Promise<Response> =>
  Promise.resolve(
    new Response(
      JSON.stringify({
        error: 'forbidden-origin',
        sentence: "Subtitle search isn't set up for this site — add a subtitle file instead.",
      }),
      { status: 403, headers: { 'Content-Type': 'application/json' } },
    ),
  )
const api = createApi({
  base: API_BASE,
  fetch: (u, i) => (searchEnabled ? fetch(u, i) : notConfigured()),
  jwt: () => app.session.jwt,
})

// ── views ──
const openOffice = () => {
  office.open(app.user)
  layers()
}
const strips = [ticketStrip(openOffice), ticketStrip(openOffice), ticketStrip()]
const [landingStrip, leaderStrip, officeStrip] = strips as [
  ReturnType<typeof ticketStrip>,
  ReturnType<typeof ticketStrip>,
  ReturnType<typeof ticketStrip>,
]

// The subtitle-only picker lives outside every layer (so it is never inert), and joins the page
// only when first used: the landing keeps exactly one file input.
const subInput = h('input', {
  type: 'file',
  class: 'sr',
  tabindex: -1,
  accept: '.srt,.vtt,.ass,.ssa,text/vtt,application/x-subrip',
  'aria-label': 'Choose a subtitle file',
})
subInput.addEventListener('change', () => {
  const f = subInput.files?.[0]
  subInput.value = ''
  if (f) void onFiles([f])
})
const pickSubtitle = () => {
  if (!subInput.isConnected) document.body.append(subInput)
  subInput.click()
}

const lite = liteLanding({
  now: new Date(),
  releasesUrl: RELEASES,
  searchEnabled,
  language,
  onFiles: (files) => void onFiles(files),
  onOffice: openOffice,
  onLanguage: (code) => setLanguage(code),
  strip: landingStrip.el,
})
const lead = leader(
  {
    onChoose: (action) => dispatch({ type: 'choose', at: now(), action }),
    onPick: (candidate) => dispatch({ type: 'pick', at: now(), candidate }),
    onManual: (query) => dispatch({ type: 'manual-query', at: now(), query }),
    onSidecar: pickSubtitle,
  },
  leaderStrip.el,
)
const aud = auditorium({
  onBack: () => leaveAuditorium(),
  onBooth: () => openBooth(),
  onAddSubtitle: pickSubtitle,
  onToggleSubs: () => showTrack(!app.subsOn),
  onSyncStep: (k) => setDelay(syncStep(app.delay, k)),
  onSyncReset: () => setDelay(syncReset()),
  onVolume: (volume, muted) => {
    prefs.volume = volume
    prefs.muted = muted
    savePrefs(prefs)
  },
})
const sheet = booth({
  search: searchEnabled,
  onTrack: (id) => showTrack(id !== null),
  onSize: (s) => setCueSize(s),
  onSync: (v) => setDelay(v),
  onFindAnother: () =>
    dispatch({ type: 'research', at: now(), exclude: app.subtitle?.fileId ?? null }),
  onPick: (candidate) => dispatch({ type: 'pick', at: now(), candidate }),
  onClose: () => closeBooth(),
  onAddSubtitle: pickSubtitle,
  onLanguage: (code) => setLanguage(code),
  onSignIn: openOffice,
})
const office = signIn(
  {
    onSubmit: (u, p, sessionOnly) => login(u, p, sessionOnly),
    onSignOut: () => void signOut(),
    onClose: () => closeOffice(),
    signUpUrl: SIGN_UP_URL,
  },
  officeStrip.el,
)

root.dataset.sky = skyFor(new Date())
const room = h(
  'div',
  { class: 'room' },
  h('div', { class: 'sky', 'aria-hidden': 'true' }),
  h('div', { class: 'beam', 'aria-hidden': 'true' }),
  h('div', { class: 'grain', 'aria-hidden': 'true' }),
  lite.el,
)
document.body.append(room, lead.el, aud.el, sheet.el, office.el)
aud.setVolume(prefs.volume, prefs.muted)
sheet.setSize(app.cueSize)
sheet.setLanguage(language)
aud.pic.style.setProperty('--cue-size', `${CUE_SCALE[app.cueSize]}em`)

/** Only the top layer is live; everything beneath it is inert (no focus, no clicks). */
function layers(): void {
  const top = office.isOpen
    ? 'office'
    : app.noPrintEl
      ? 'noprint'
      : sheet.isOpen
        ? 'booth'
        : !aud.el.hidden
          ? 'aud'
          : !lead.el.hidden
            ? 'lead'
            : 'room'
  room.inert = top !== 'room'
  lead.el.inert = top !== 'lead'
  aud.el.inert = top !== 'aud'
  sheet.el.inert = top !== 'booth'
  if (app.noPrintEl) app.noPrintEl.inert = top !== 'noprint'
}

// ── rendering ──
function renderStrips(): void {
  if (!searchEnabled) return
  const strip = stripModel(app.session.quota, { now: new Date(), pendingTear: app.pendingTear })
  const q = app.session.quota
  const stubs = (q.remaining ?? 0) + (app.pendingTear ? 1 : 0)
  for (const s of strips) s.render(strip, q.signedIn ? stubs : 0)
  sheet.setTickets(q.signedIn ? strip.text : 'NOT SIGNED IN')
}

let boothKey = ''
function renderBooth(s: ThreadingState, failure: string | null): void {
  if (!searchEnabled) return
  const m = app.machine
  let sentence = failure ?? ''
  if (!failure) {
    if (s.phase === 'searching') sentence = 'Looking for other prints…'
    else if (s.phase === 'downloading') sentence = 'Downloading…'
    else if (s.phase === 'done' && m.listOnly && s.candidates.length > 0)
      sentence = 'Pick one — it replaces the subtitles on screen.'
  }
  const signIn = s.failure === 'unauthorized' || s.failure === 'quota-exhausted'
  const key = `${s.candidates.map((c) => c.candidate.id).join(',')}|${s.picked?.candidate.id}|${sentence}|${signIn}`
  if (key === boothKey) return
  boothKey = key
  sheet.setCandidates(s.candidates, s.picked, sentence || null, signIn)
}

function render(): void {
  const s = app.machine.state
  const sentence = s.failure ? (app.sentence ?? FAILURE_SENTENCE[s.failure]) : null
  lead.render(app.machine, sentence)
  if (sheet.isOpen) renderBooth(s, sentence)
  renderStrips()
}

// ── the machine driver ──
function dispatch(e: ThreadingEvent): void {
  if (!searchEnabled) return
  const wasPending = isPending()
  const step = reduce(app.machine, e)
  app.machine = step.machine
  if (e.type !== 'failed' && app.machine.state.failure === null) app.sentence = null
  render()
  for (const effect of step.effects) perform(effect)
  if (!wasPending && isPending()) requestAnimationFrame(tick)
}

const isPending = () => {
  const s = app.machine.state
  return (
    s.failure === null &&
    (s.phase === 'hashing' || s.phase === 'searching' || s.phase === 'downloading')
  )
}

function tick(): void {
  if (!isPending()) return
  dispatch({ type: 'tick', at: now() })
  requestAnimationFrame(tick)
}

function perform(effect: Effect): void {
  switch (effect.kind) {
    case 'hash':
      void doHash()
      break
    case 'search':
      void doSearch(effect.rung, effect.query)
      break
    case 'download':
      void doDownload(effect.candidate)
      break
    case 'abort':
      app.controller.abort()
      app.controller = new AbortController()
      break
    case 'flash':
      if (!aud.el.hidden) dispatch({ type: 'flashed', at: now() })
      else void lead.flash(effect.ms).then(() => dispatch({ type: 'flashed', at: now() }))
      break
    case 'play':
      enterAuditorium()
      break
    case 'show-sign-in':
      openOffice()
      break
    case 'show-manual':
      lead.showManual()
      break
    case 'announce':
      break // the leader's aria-live label changes once per phase in render()
  }
}

// ── opening files ──
async function onFiles(files: File[]): Promise<void> {
  const subs = files.filter((f) => sidecarKind(f.name) !== null)
  const film = files.find((f) => sidecarKind(f.name) === null)
  if (film) {
    await openFile(film, subs[0] ?? null)
    return
  }
  const sub = subs[0]
  if (!sub) return
  if (app.file && !app.noPrintEl) {
    await attachSidecar(sub)
    // A subtitle file chosen while the leader is still threading: no search is needed.
    if (!lead.el.hidden) dispatch({ type: 'choose', at: now(), action: 'skip' })
    return
  }
  lite.setSentence("That's a subtitle file — open the film first, then add its subtitles.")
}

async function openFile(file: File, sidecar: File | null): Promise<void> {
  teardown()
  lite.setSentence(null)
  app.file = file
  app.parsed = parsePath(file.name)
  app.hash = null
  app.printOk = null
  const title = app.parsed?.title || file.name.replace(/\.[^.]+$/, '')
  document.title = `${title} · ${APP_TITLE}`
  aud.setTitle(title)
  root.dataset.house = 'down' // the ONE tween: --house 1 → 0 over 900 ms
  app.videoUrl = URL.createObjectURL(file)
  aud.video.src = app.videoUrl
  aud.video.load()

  if (searchEnabled && !sidecar) {
    lead.setMeta(file.size)
    lead.el.hidden = false
    layers()
    lead.focus()
    dispatch({ type: 'open', at: now(), parsed: app.parsed, quota: app.session.quota })
  } else {
    // Straight to the picture: the viewer brought their own subtitles, or there is no search.
    void hashInBackground(file)
    if (sidecar) await attachSidecar(sidecar)
    if (app.file !== file) return
    enterAuditorium()
  }

  const sniff = sniffHead(file)
  const ok = await playable(aud.video)
  if (app.file !== file) return
  app.printOk = ok
  if (!ok) await showNoPrint(file, await sniff)
  else void checkPictureAndSound(file, await sniff)
}

const sniffHead = async (file: File): Promise<PrintSniff> =>
  sniffPrint(new Uint8Array(await file.slice(0, SNIFF_BYTES).arrayBuffer()), file.name)

/** The print is projectable when metadata arrives with a picture (or at least sound). */
function playable(video: HTMLVideoElement): Promise<boolean> {
  return new Promise((resolve) => {
    const done = (ok: boolean) => {
      clearTimeout(timer)
      video.removeEventListener('loadedmetadata', onMeta)
      video.removeEventListener('error', onError)
      resolve(ok)
    }
    const onMeta = () => done(video.videoWidth > 0 || video.duration > 0)
    const onError = () => done(false)
    const timer = setTimeout(() => done(video.readyState >= 1), PLAYABLE_WITHIN_MS)
    if (video.readyState >= 1) {
      onMeta()
      return
    }
    video.addEventListener('loadedmetadata', onMeta)
    video.addEventListener('error', onError)
  })
}

interface MediaProbe {
  mozHasAudio?: boolean
  webkitAudioDecodedByteCount?: number
  audioTracks?: { length: number }
}

/** Does the element actually produce sound? null when the browser cannot say. */
function hasAudio(v: HTMLVideoElement): boolean | null {
  const p = v as HTMLVideoElement & MediaProbe
  if (typeof p.mozHasAudio === 'boolean') return p.mozHasAudio
  if (typeof p.webkitAudioDecodedByteCount === 'number') return p.webkitAudioDecodedByteCount > 0
  if (p.audioTracks) return p.audioTracks.length > 0
  return null
}

/**
 * A print that plays can still be silent (AC-3 / DTS / E-AC-3 in an MKV) or blind (HEVC in a
 * browser without it). Say so once, without stopping the film.
 */
async function checkPictureAndSound(file: File, sniff: PrintSniff): Promise<void> {
  const cap = app.capability ?? (await probe())
  if (app.file !== file) return
  const video = aud.video
  if (video.videoWidth === 0 && sniff.video) {
    const missing = noPrintReason({ ...sniff, audio: null }, cap).missing
    aud.notice(
      `No picture: this browser has no ${missing ?? sniff.video} decoder — only the sound plays.`,
      APP_LINK,
    )
  }
  if (!sniff.audio) return
  const missing = noPrintReason({ ...sniff, video: null }, cap).missing
  const check = () => {
    if (app.file !== file) return
    const audible = hasAudio(video)
    if (audible === true || (audible === null && missing === null)) return
    aud.notice(
      missing
        ? `No sound: this browser has no ${missing} decoder.`
        : "No sound: this browser can't decode this film's audio.",
      APP_LINK,
    )
  }
  const later = () => setTimeout(check, SOUND_CHECK_MS)
  if (!video.paused && video.readyState >= 3) later()
  else video.addEventListener('playing', later, { once: true })
}

// ── effects ──
async function hashOf(file: File): Promise<MovieHash | null> {
  try {
    return await osHash(file)
  } catch (e) {
    // < 128 KiB or unreadable: SILENT — "3" completes and "2" searches by name.
    if (!isFileTooSmall(e) && !(e instanceof HashUnavailable)) throw e
    return null
  }
}

/** Fingerprint-keyed memory for this film: the sync offset and where you left it. */
function remember(file: File, hash: MovieHash | null): void {
  app.hash = hash
  app.resumeKey = hash ?? `${file.name}|${file.size}`
  setDelay(offsets.recall(hash), false)
  void maybeResume(file)
  cacheSidecar()
}

async function hashInBackground(file: File): Promise<void> {
  const hash = await hashOf(file)
  if (app.file !== file) return
  remember(file, hash)
  if (!hash || app.subtitle) return
  const cached = await idb.subtitles.get(hash, idb.SIDECAR_LANG).catch(() => undefined)
  if (!cached || app.file !== file || app.subtitle) return
  setCues(parseSrt(cached.vttText), {
    label: cached.release ?? 'Your subtitle file',
    status: 'yours',
    fileId: null,
  })
}

async function doHash(): Promise<void> {
  const file = app.file
  if (!file) return
  const hash = await hashOf(file)
  if (app.file !== file) return
  remember(file, hash)
  const lang = app.session.languages[0] ?? 'en'
  const cached = hash
    ? ((await idb.subtitles.get(hash, idb.SIDECAR_LANG).catch(() => undefined)) ??
      (await idb.subtitles.get(hash, lang).catch(() => undefined)))
    : undefined
  if (app.file !== file) return
  if (cached) {
    // Rung 0b: re-attach from IndexedDB — zero requests, zero tickets, works offline.
    const yours = cached.provider === 'sidecar'
    setCues(parseSrt(cached.vttText), {
      label: yours
        ? (cached.release ?? 'Your subtitle file')
        : `${languageLabel(cached.language)} · ${cached.release ?? 'OpenSubtitles'}`,
      status: yours ? 'yours' : cached.syncedByHash ? 'synced' : 'by-name',
      fileId: null,
    })
    app.inSync = cached.syncedByHash
    dispatch({ type: 'attached', at: now(), inSync: cached.syncedByHash })
    return
  }
  dispatch({ type: 'hashed', at: now(), hash })
}

async function doSearch(rung: SearchRung, query?: string): Promise<void> {
  const langs = app.session.languages
  const parsed = app.parsed ?? (app.file ? parseName(app.file.name) : null)
  let params: Record<string, string | number | null | undefined>
  if (rung === 'hash' && app.hash) params = hashSearchParams(app.hash, langs)
  else if (rung === 'manual' && query) params = { languages: langs.join(','), query }
  else if (rung === 'filename' && parsed) params = nameSearchParams(parsed, langs)
  else {
    dispatch({ type: 'failed', at: now(), failure: 'no-results' })
    return
  }
  const r = await api.search(params, app.controller.signal)
  if (!r.ok) {
    if (r.failure === 'cancelled') return
    app.sentence = r.sentence
    dispatch({ type: 'failed', at: now(), failure: r.failure })
    return
  }
  const candidates = rank(candidatesFromSearch(r.value), {
    parsed,
    containerFps: null, // the browser does not expose the container frame rate
    preferHI: app.session.preferHearingImpaired,
    languages: langs,
  })
  dispatch({ type: 'searched', at: now(), candidates })
}

async function doDownload(sc: ScoredCandidate): Promise<void> {
  const signal = app.controller.signal
  const r = await api.download(Number(sc.candidate.id), signal)
  if (!r.ok) {
    if (r.failure === 'cancelled') return
    if (r.download) app.session.quota = quotaFromDownload(r.download, app.session.quota)
    app.sentence = r.sentence
    dispatch({ type: 'failed', at: now(), failure: r.failure, quota: app.session.quota })
    return
  }
  app.session.quota = quotaFromDownload(r.value, app.session.quota)
  void persistSession()
  const file = await api.subtitleFile(r.value.link, signal)
  if (!file.ok) {
    if (file.failure === 'cancelled') return
    app.sentence = file.sentence
    dispatch({ type: 'failed', at: now(), failure: file.failure })
    return
  }
  const cues = parseSrt(file.value)
  if (cues.length === 0) {
    app.sentence = 'That print was empty — pick another.'
    dispatch({ type: 'failed', at: now(), failure: 'no-results' })
    return
  }
  const c = sc.candidate
  app.inSync = c.moviehashMatch
  setCues(cues, {
    label: `${languageLabel(c.language)} · ${c.release ?? 'OpenSubtitles'}`,
    status: c.moviehashMatch ? 'synced' : 'by-name',
    fileId: c.id,
  })
  if (app.hash) {
    const vttText = toVtt(cues)
    void idb.subtitles
      .put({
        hash: app.hash,
        language: c.language,
        provider: c.provider,
        release: c.release,
        syncedByHash: c.moviehashMatch,
        vttText,
        bytes: vttText.length,
        fetchedAt: Date.now(),
      })
      .catch(() => undefined)
  }
  // The strip decrements AFTER the tear, never before.
  app.pendingTear = true
  renderStrips()
  await leaderStrip.tear()
  app.pendingTear = false
  dispatch({ type: 'attached', at: now(), inSync: c.moviehashMatch, quota: app.session.quota })
}

// ── subtitles on the picture ──
/** Replace whatever is on screen with these cues (an ASS renderer is torn down first). */
function setCues(cues: Cue[], sub: Subtitle): void {
  app.ass?.destroy()
  app.ass = null
  app.cues = cues
  app.subtitle = sub
  app.subsOn = true
  applyTrack()
  renderTracks()
}

function applyTrack(): void {
  const video = aud.video
  for (const t of video.querySelectorAll('track')) t.remove()
  if (app.trackUrl) URL.revokeObjectURL(app.trackUrl)
  app.trackUrl = null
  if (!app.cues) return
  app.trackUrl = URL.createObjectURL(
    new Blob([toVtt(app.cues, Math.round(app.delay * 1000))], { type: 'text/vtt' }),
  )
  const lang = app.session.languages[0] ?? 'en'
  const track = h('track', {
    kind: 'subtitles',
    srclang: lang,
    label: app.subtitle?.label ?? languageLabel(lang),
    src: app.trackUrl,
    default: app.subsOn,
  })
  video.append(track)
  // The viewer's Off survives a sync change: the re-emitted track keeps their choice.
  track.track.mode = app.subsOn ? 'showing' : 'hidden'
}

function renderTracks(): void {
  const sub = app.subtitle
  const list: BoothTrack[] = sub ? [{ id: 'current', label: sub.label, status: sub.status }] : []
  sheet.setTracks(list, sub && app.subsOn ? 'current' : null)
  aud.setSubs(sub !== null, app.subsOn)
}

function showTrack(on: boolean): void {
  if (!app.subtitle) {
    if (on) pickSubtitle()
    return
  }
  app.subsOn = on
  for (const t of aud.video.textTracks) t.mode = on ? 'showing' : 'hidden'
  app.ass?.setVisible(on)
  renderTracks()
}

async function attachSidecar(file: File): Promise<void> {
  const kind = sidecarKind(file.name)
  if (!kind) return
  const text = decodeSubtitle(new Uint8Array(await file.arrayBuffer()))
  if (kind === 'ass') {
    const { attachAss } = await import('./ui/ass')
    const ass = await attachAss(aud.video, text)
    // Only one subtitle at a time: the text track (if any) goes.
    app.ass?.destroy()
    app.cues = null
    app.sidecarToCache = null
    applyTrack()
    app.ass = ass
    app.subtitle = { label: file.name, status: 'yours', fileId: null }
    app.subsOn = true
    ass.setDelay(app.delay)
    ass.setScale(CUE_SCALE[app.cueSize])
    renderTracks()
    return
  }
  const cues = parseSidecar(kind, text) ?? []
  if (cues.length === 0) {
    aud.notice(`${file.name} has no subtitles this player can read.`)
    return
  }
  app.inSync = false
  setCues(cues, { label: file.name, status: 'yours', fileId: null })
  app.sidecarToCache = { cues, name: file.name }
  cacheSidecar()
}

/** Remember a viewer's own SRT/VTT by moviehash, so the film re-attaches it next time. */
function cacheSidecar(): void {
  const pending = app.sidecarToCache
  if (!pending || !app.hash) return
  app.sidecarToCache = null
  const vttText = toVtt(pending.cues)
  void idb.subtitles
    .put({
      hash: app.hash,
      language: idb.SIDECAR_LANG,
      provider: 'sidecar',
      release: pending.name,
      syncedByHash: false,
      vttText,
      bytes: vttText.length,
      fetchedAt: Date.now(),
    })
    .catch(() => undefined)
}

let resync: ReturnType<typeof setTimeout> | undefined
function setDelay(v: number, remember = true): void {
  app.delay = snap(v)
  sheet.setSync(app.delay)
  aud.setSubDelay(app.delay)
  app.ass?.setDelay(app.delay)
  clearTimeout(resync)
  resync = setTimeout(applyTrack, RESYNC_DEBOUNCE_MS) // re-emit the shifted VTT
  if (remember && app.hash)
    void idb.offsets.put(offsets.remember(app.hash, app.delay)).catch(() => undefined)
}

function setCueSize(s: CueSize): void {
  app.cueSize = s
  aud.pic.style.setProperty('--cue-size', `${CUE_SCALE[s]}em`)
  app.ass?.setScale(CUE_SCALE[s])
  prefs.cueSize = s
  savePrefs(prefs)
}

function setLanguage(code: string): void {
  app.session.languages = [code]
  app.machine = { ...app.machine, language: code }
  lite.setLanguage(code)
  sheet.setLanguage(code)
  prefs.language = code
  savePrefs(prefs)
}

// ── resume ──
async function maybeResume(file: File): Promise<void> {
  const key = app.resumeKey
  if (!key) return
  const point = await idb.resume.get(key).catch(() => undefined)
  if (!point || app.file !== file) return
  const video = aud.video
  const apply = () => {
    if (app.file !== file) return
    const dur = Number.isFinite(video.duration) ? video.duration : point.duration
    if (point.position < RESUME_MIN_S || point.position > dur - RESUME_TAIL_S) return
    if (video.currentTime > RESUME_MIN_S) return // the viewer already moved on
    video.currentTime = point.position
    aud.offerResume(point.position, () => {
      video.currentTime = 0
      void idb.resume.clear(key).catch(() => undefined)
    })
  }
  if (video.readyState >= 1) apply()
  else video.addEventListener('loadedmetadata', apply, { once: true })
}

let lastSave = 0
function saveResume(force = false): void {
  const key = app.resumeKey
  const video = aud.video
  if (!key || !app.file || !Number.isFinite(video.duration) || video.duration <= 0) return
  const t = performance.now()
  if (!force && t - lastSave < RESUME_SAVE_MS) return
  lastSave = t
  const position = video.currentTime
  if (position > video.duration - RESUME_TAIL_S || video.ended) {
    void idb.resume.clear(key).catch(() => undefined)
  } else if (position >= RESUME_MIN_S) {
    void idb.resume
      .put(key, { position, duration: video.duration, savedAt: Date.now() })
      .catch(() => undefined)
  }
}
aud.video.addEventListener('timeupdate', () => saveResume())
aud.video.addEventListener('pause', () => saveResume(true))
aud.video.addEventListener('ended', () => saveResume(true))
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') saveResume(true)
})

// ── lighting states ──
function enterAuditorium(): void {
  if (app.printOk === false || !app.file) return
  lead.el.hidden = true
  if (!aud.el.hidden) {
    layers()
    return
  }
  aud.el.hidden = false
  renderTracks()
  layers()
  aud.focusPlay()
  void aud.video.play().catch(() => undefined)
  aud.revealControls()
}

function leaveAuditorium(): void {
  closeBooth()
  teardown()
  aud.el.hidden = true
  lead.el.hidden = true
  root.dataset.house = 'up'
  layers()
  lite.el.querySelector<HTMLElement>('.doors')?.focus()
}

function teardown(): void {
  saveResume(true)
  app.controller.abort()
  app.controller = new AbortController()
  if (app.machine.state.phase !== 'idle' && app.machine.state.phase !== 'done') {
    app.machine = reduce(app.machine, { type: 'cancel', at: now() }).machine
  }
  if (document.fullscreenElement) void document.exitFullscreen().catch(() => undefined)
  aud.video.pause()
  aud.video.removeAttribute('src')
  aud.video.load()
  for (const t of aud.video.querySelectorAll('track')) t.remove()
  if (app.videoUrl) URL.revokeObjectURL(app.videoUrl)
  if (app.trackUrl) URL.revokeObjectURL(app.trackUrl)
  app.videoUrl = null
  app.trackUrl = null
  app.cues = null
  app.ass?.destroy()
  app.ass = null
  app.subtitle = null
  app.sidecarToCache = null
  app.subsOn = true
  app.file = null
  app.resumeKey = null
  app.noPrintEl?.remove()
  app.noPrintEl = null
  aud.clearNotices()
  aud.setTitle(null)
  document.title = APP_TITLE
  renderTracks()
}

let wasPlaying = false
function openBooth(): void {
  if (sheet.isOpen) return
  wasPlaying = !aud.video.paused
  aud.video.pause() // booth glass only ever sits over a PAUSED frame
  boothKey = ''
  renderTracks()
  sheet.open()
  render()
  layers()
}
function closeBooth(): void {
  if (!sheet.isOpen) return
  sheet.close()
  layers()
  if (wasPlaying && app.file) void aud.video.play().catch(() => undefined)
}
function closeOffice(): void {
  office.close()
  layers()
}

async function showNoPrint(file: File, sniff: PrintSniff): Promise<void> {
  if (app.machine.state.phase !== 'idle' && app.machine.state.phase !== 'done') {
    dispatch({ type: 'cancel', at: now() }) // no ticket is spent on a print we cannot show
  }
  lead.el.hidden = true
  aud.el.hidden = true
  aud.video.pause()
  const cap = app.capability ?? (await probe())
  if (app.file !== file) return
  const card = noPrint({
    reason: noPrintReason(sniff, cap),
    releasesUrl: RELEASES,
    onOpenAnother: () => {
      leaveAuditorium()
      lite.input.click()
    },
  })
  app.noPrintEl = card
  document.body.append(card)
  layers()
  card.querySelector<HTMLElement>('.btn')?.focus()
}

// ── the ticket office ──
async function login(
  username: string,
  password: string,
  sessionOnly: boolean,
): Promise<string | null> {
  const r = await api.login(username, password)
  if (!r.ok) return r.status === 401 ? "Those details didn't open the ticket office." : r.sentence
  app.session.jwt = r.value.token
  app.session.quota = quotaFromLogin(r.value, app.session.quota)
  app.user = username
  app.sessionOnly = sessionOnly
  await persistSession()
  closeOffice()
  dispatch({ type: 'signed-in', at: now(), quota: app.session.quota })
  return null
}

async function signOut(): Promise<void> {
  app.session.jwt = null
  app.session.quota = ANONYMOUS
  app.user = null
  await persistSession()
  closeOffice()
  render()
}

const persistSession = () =>
  idb.saveSession(app.session, app.user, app.sessionOnly).catch(() => undefined)

// ── startup ──
async function probe(): Promise<Capability> {
  const v = document.createElement('video')
  app.capability = await probeCapability({
    canPlayType: (m) => v.canPlayType(m),
    VideoDecoder: 'VideoDecoder' in window ? window.VideoDecoder : undefined,
    AudioDecoder: 'AudioDecoder' in window ? window.AudioDecoder : undefined,
  })
  lite.setCapability(app.capability)
  return app.capability
}

async function restore(): Promise<void> {
  if (!searchEnabled) return
  const loaded = await idb.loadSession().catch(() => null)
  if (loaded) {
    // The language is a per-browser preference now; the stored session never overrides it.
    app.session = { ...app.session, ...loaded.session, languages: app.session.languages }
    app.user = loaded.user
  }
  if (app.session.jwt) {
    const info = await api.userInfo()
    if (info.ok) app.session.quota = quotaFromUserInfo(info.value, app.session.quota)
    else if (info.failure === 'unauthorized') {
      app.session.jwt = null
      app.session.quota = ANONYMOUS
    }
  } else {
    app.session.quota = ANONYMOUS
  }
  render()
}

async function restoreOffsets(): Promise<void> {
  for (const o of await idb.offsets.all().catch(() => []))
    offsets.remember(o.hash, o.delayMs / 1000)
}

// ── keyboard ──
document.addEventListener('keydown', (e) => {
  if (e.defaultPrevented) return
  const t = e.target
  const typing =
    (t instanceof HTMLInputElement && !['range', 'checkbox', 'file'].includes(t.type)) ||
    t instanceof HTMLSelectElement ||
    t instanceof HTMLTextAreaElement
  if (e.key === 'Escape') {
    // Esc always goes exactly one lighting state up.
    if (office.isOpen) closeOffice()
    else if (aud.closeMenus() || aud.closeCueSheet()) return
    else if (sheet.isOpen) closeBooth()
    else if (app.noPrintEl) leaveAuditorium()
    else if (!lead.el.hidden) dispatch({ type: 'choose', at: now(), action: 'skip' })
    else if (!aud.el.hidden) leaveAuditorium()
    return
  }
  if (typing || office.isOpen || sheet.isOpen || app.noPrintEl) return
  // The volume slider keeps its own arrow keys.
  if (t instanceof HTMLInputElement && t.type === 'range' && e.key.startsWith('Arrow')) return
  if (!aud.el.hidden) aud.handleKey(e)
})

// ── drag and drop, anywhere on the page ──
// preventDefault on every dragover/drop: otherwise a film dropped beside the frame makes the
// browser navigate away to play it.
let dragDepth = 0
const carriesFiles = (e: DragEvent) => e.dataTransfer?.types.includes('Files') === true
window.addEventListener('dragenter', (e) => {
  if (!carriesFiles(e)) return
  dragDepth++
  lite.setDragging(true)
})
window.addEventListener('dragover', (e) => {
  e.preventDefault()
  if (e.dataTransfer) e.dataTransfer.dropEffect = carriesFiles(e) ? 'copy' : 'none'
})
window.addEventListener('dragleave', () => {
  dragDepth = Math.max(0, dragDepth - 1)
  if (dragDepth === 0) lite.setDragging(false)
})
window.addEventListener('drop', (e) => {
  e.preventDefault()
  dragDepth = 0
  lite.setDragging(false)
  const files = [...(e.dataTransfer?.files ?? [])]
  if (files.length > 0) void onFiles(files)
})

// ── an installed Lite opening a film from the OS ("Open with…", file_handlers) ──
interface LaunchParamsLike {
  files: readonly FileSystemFileHandle[]
}
const launchQueue = (
  window as unknown as {
    launchQueue?: { setConsumer(cb: (p: LaunchParamsLike) => void): void }
  }
).launchQueue
launchQueue?.setConsumer((p) => {
  void Promise.all(p.files.map((f) => f.getFile())).then((files) => {
    if (files.length > 0) void onFiles(files)
  })
})

renderStrips()
layers()
void probe()
void restore()
void restoreOffsets()
