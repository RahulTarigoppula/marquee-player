// Marquee Lite: the wiring. One app state, DOM updates by CSS custom properties and textContent,
// overlays toggled with `hidden` (and everything beneath the top layer made `inert`).
// With a Worker (VITE_API_BASE set) the ritual is:
//   drop → capability probe → moviehash → IndexedDB (a hit costs ZERO requests) → search →
//   score → auto-pick → download (signed in, via the Worker) → subtitle-file → SRT→VTT →
//   <track> via a Blob URL → play.
// Without one, a film goes straight to the picture; the moviehash still keys the local cache
// (a subtitle file you added before re-attaches), the sync offset and the resume point.
// The pieces live in app/ (subtitles, resume, print checks, page input) and ui/ (the views).
import './styles/tokens.css'
import './styles/app.css'
import './styles/player.css'
import { installDrop, installKeyboard, installLaunchQueue } from './app/input'
import { checkPictureAndSound, hashOf, playable, sniffHead } from './app/print'
import { resumeKeeper } from './app/resume'
import { subtitles } from './app/subtitles'
import { API_BASE, releasesUrl, SIGN_UP_URL, searchEnabled } from './config'
import { candidatesFromSearch, createApi, hashSearchParams, nameSearchParams } from './engine/api'
import { noPrintReason, type PrintSniff, probeCapability } from './engine/capability'
import { parseName, parsePath } from './engine/filename'
import { defaultLanguage, languageLabel } from './engine/languages'
import { rank } from './engine/scoring'
import { sidecarKind } from './engine/sidecar'
import { parseSrt, toVtt } from './engine/srt2vtt'
import { OffsetBook, reset as syncReset, step as syncStep } from './engine/syncRule'
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
import { auditorium } from './ui/auditorium'
import { booth, CUE_SCALE, type CueSize } from './ui/booth'
import { h } from './ui/dom'
import { leader } from './ui/leader'
import { liteLanding, skyFor } from './ui/lite'
import { noPrint } from './ui/noPrint'
import { signIn } from './ui/signIn'
import { ticketStrip } from './ui/ticketStrip'

const APP_TITLE = 'Marquee Lite'
const root = document.documentElement
const now = () => performance.now()

// ── state ──
const prefs = loadPrefs()
const language =
  prefs.language ?? defaultLanguage(navigator.languages?.length ? navigator.languages : ['en'])
const RELEASES = releasesUrl(location)
const APP_LINK = { href: RELEASES, label: 'Get the Windows / Android app' }

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
  file: null as File | null,
  parsed: null as ParsedName | null,
  hash: null as MovieHash | null,
  printOk: null as boolean | null,
  pendingTear: false,
  controller: new AbortController(),
  videoUrl: null as string | null,
  noPrintEl: null as HTMLElement | null,
}
const offsets = new OffsetBook()
// With no Worker configured (VITE_API_BASE empty) nothing is ever fetched: the search UI is
// not shown at all, and this stub is only a safety net.
const notConfigured = (): Promise<Response> =>
  Promise.resolve(
    new Response(
      JSON.stringify({
        error: 'forbidden-origin',
        sentence: "Subtitle search isn't set up for this site. Add a subtitle file instead.",
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
  onToggleSubs: () => subs.toggle(),
  onSyncStep: (k) => subs.setDelay(syncStep(subs.delay, k)),
  onSyncReset: () => subs.setDelay(syncReset()),
  onVolume: (volume, muted) => {
    prefs.volume = volume
    prefs.muted = muted
    savePrefs(prefs)
  },
})
const sheet = booth({
  search: searchEnabled,
  onTrack: (id) => subs.show(id !== null),
  onSize: (s) => subs.setCueSize(s),
  onSync: (v) => subs.setDelay(v),
  onFindAnother: () =>
    dispatch({ type: 'research', at: now(), exclude: subs.current?.fileId ?? null }),
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
const subs = subtitles({
  aud,
  sheet,
  language: () => app.session.languages[0] ?? 'en',
  hash: () => app.hash,
  pickFile: pickSubtitle,
  onDelay: (hash, delay) => {
    void idb.offsets.put(offsets.remember(hash, delay)).catch(() => undefined)
  },
  cueSize: prefs.cueSize,
  onCueSize: (s: CueSize) => {
    prefs.cueSize = s
    savePrefs(prefs)
  },
})
const resume = resumeKeeper(aud.video, aud.offerResume)

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
aud.setCueScale(CUE_SCALE[prefs.cueSize])
sheet.setSize(prefs.cueSize)
sheet.setLanguage(language)

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
      sentence = 'Pick one. It replaces the subtitles on screen.'
  }
  const signIn = s.failure === 'unauthorized' || s.failure === 'quota-exhausted'
  const key = `${s.candidates.map((c) => c.candidate.id).join(',')}|${s.picked?.candidate.id}|${sentence}|${signIn}`
  if (key === boothKey) return
  boothKey = key
  sheet.setCandidates(s.candidates, s.picked, sentence || null, signIn)
}

/** `frame`: a sweep tick, where only the leader can have changed. */
function render(frame = false): void {
  const s = app.machine.state
  const sentence = s.failure ? (app.sentence ?? FAILURE_SENTENCE[s.failure]) : null
  lead.render(app.machine, sentence)
  if (frame) return
  if (sheet.isOpen) renderBooth(s, sentence)
  renderStrips()
}

// ── the machine driver ──
function dispatch(e: ThreadingEvent): void {
  if (!searchEnabled) return
  const wasPending = isPending()
  const before = app.machine.state
  const step = reduce(app.machine, e)
  app.machine = step.machine
  const s = app.machine.state
  if (e.type !== 'failed' && s.failure === null) app.sentence = null
  const sweepOnly =
    e.type === 'tick' &&
    step.effects.length === 0 &&
    s.phase === before.phase &&
    s.failure === before.failure
  render(sweepOnly)
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

/** The leader's sweep: one frame-rate loop, only while a phase is in flight. */
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
  const subtitleFiles = files.filter((f) => sidecarKind(f.name) !== null)
  const film = files.find((f) => sidecarKind(f.name) === null)
  if (film) {
    await openFile(film, subtitleFiles[0] ?? null)
    return
  }
  const sub = subtitleFiles[0]
  if (!sub) return
  if (app.file && !app.noPrintEl) {
    await subs.attach(sub)
    // A subtitle file chosen while the leader is still threading: no search is needed.
    if (!lead.el.hidden) dispatch({ type: 'choose', at: now(), action: 'skip' })
    return
  }
  lite.setSentence("That's a subtitle file. Open the film first, then add its subtitles.")
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
    if (sidecar) await subs.attach(sidecar)
    if (app.file !== file) return
    enterAuditorium()
  }

  const sniff = sniffHead(file)
  const ok = await playable(aud.video)
  if (app.file !== file) return
  app.printOk = ok
  if (!ok) {
    await showNoPrint(file, await sniff)
    return
  }
  const [head, cap] = await Promise.all([sniff, capability()])
  if (app.file !== file) return
  checkPictureAndSound(aud.video, head, cap, () => app.file === file, aud.notice, APP_LINK)
}

// ── effects ──
/** Fingerprint-keyed memory for this film: the sync offset and where you left it. */
function remember(file: File, hash: MovieHash | null): void {
  app.hash = hash
  resume.start(hash ?? `${file.name}|${file.size}`)
  subs.hashKnown()
  void loadOffsets().then(() => {
    if (app.file === file) subs.setDelay(offsets.recall(hash), false)
  })
}

async function hashInBackground(file: File): Promise<void> {
  const hash = await hashOf(file)
  if (app.file !== file) return
  remember(file, hash)
  if (!hash || subs.current) return
  const cached = await idb.subtitles.get(hash, idb.SIDECAR_LANG).catch(() => undefined)
  if (!cached || app.file !== file || subs.current) return
  subs.setCues(parseSrt(cached.vttText), {
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
    // Rung 0b: re-attach from IndexedDB. Zero requests, zero tickets, works offline.
    const yours = cached.provider === 'sidecar'
    subs.setCues(parseSrt(cached.vttText), {
      label: yours
        ? (cached.release ?? 'Your subtitle file')
        : `${languageLabel(cached.language)} · ${cached.release ?? 'OpenSubtitles'}`,
      status: yours ? 'yours' : cached.syncedByHash ? 'synced' : 'by-name',
      fileId: null,
    })
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
    app.sentence = 'That print was empty. Pick another.'
    dispatch({ type: 'failed', at: now(), failure: 'no-results' })
    return
  }
  const c = sc.candidate
  subs.setCues(cues, {
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

function setLanguage(code: string): void {
  app.session.languages = [code]
  app.machine = { ...app.machine, language: code }
  lite.setLanguage(code)
  sheet.setLanguage(code)
  prefs.language = code
  savePrefs(prefs)
}

// ── lighting states ──
function enterAuditorium(): void {
  if (app.printOk === false || !app.file) return
  lead.el.hidden = true
  if (!aud.el.hidden) {
    layers()
    return
  }
  aud.el.hidden = false
  subs.render()
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

/** Close the film: every Blob URL revoked, every renderer destroyed, the position saved. */
function teardown(): void {
  resume.stop()
  app.controller.abort()
  app.controller = new AbortController()
  if (app.machine.state.phase !== 'idle' && app.machine.state.phase !== 'done') {
    app.machine = reduce(app.machine, { type: 'cancel', at: now() }).machine
  }
  if (document.fullscreenElement) void document.exitFullscreen().catch(() => undefined)
  aud.video.pause()
  aud.video.removeAttribute('src')
  aud.video.load()
  if (app.videoUrl) URL.revokeObjectURL(app.videoUrl)
  app.videoUrl = null
  subs.clear()
  app.file = null
  app.hash = null
  app.noPrintEl?.remove()
  app.noPrintEl = null
  aud.clearNotices()
  aud.setTitle(null)
  document.title = APP_TITLE
}

let wasPlaying = false
function openBooth(): void {
  if (sheet.isOpen) return
  wasPlaying = !aud.video.paused
  aud.video.pause() // booth glass only ever sits over a PAUSED frame
  boothKey = ''
  subs.render()
  aud.setBoothOpen(true)
  sheet.open()
  render()
  layers()
}
function closeBooth(): void {
  if (!sheet.isOpen) return
  sheet.close()
  aud.setBoothOpen(false)
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
  const cap = await capability()
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
// The first canPlayType() in a fresh browser process starts its media stack, which can hold the
// main thread for a second or more. So the probe waits until the landing has painted, and every
// caller shares the one probe.
let probed: Promise<Capability> | null = null
function capability(): Promise<Capability> {
  probed ??= (async () => {
    const v = document.createElement('video')
    const cap = await probeCapability({
      canPlayType: (m) => v.canPlayType(m),
      VideoDecoder: 'VideoDecoder' in window ? window.VideoDecoder : undefined,
      AudioDecoder: 'AudioDecoder' in window ? window.AudioDecoder : undefined,
    })
    lite.setCapability(cap)
    return cap
  })()
  return probed
}

// Remembered sync offsets, read once from IndexedDB the first time they are needed (or once the
// landing is idle, whichever comes first).
let offsetsLoaded: Promise<void> | null = null
function loadOffsets(): Promise<void> {
  offsetsLoaded ??= idb.offsets
    .all()
    .catch(() => [])
    .then((stored) => {
      for (const o of stored) offsets.remember(o.hash, o.delayMs / 1000)
    })
  return offsetsLoaded
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

/** After the first paint, when the main thread is free (or within a second regardless). */
function afterPaint(fn: () => void): void {
  requestAnimationFrame(() =>
    setTimeout(() => {
      if ('requestIdleCallback' in window) requestIdleCallback(fn, { timeout: 1000 })
      else fn()
    }, 0),
  )
}

// ── page input ──
installKeyboard({
  onEscape() {
    // Esc always goes exactly one lighting state up.
    if (office.isOpen) closeOffice()
    else if (aud.closeMenus() || aud.closeCueSheet()) return
    else if (sheet.isOpen) closeBooth()
    else if (app.noPrintEl) leaveAuditorium()
    else if (!lead.el.hidden) dispatch({ type: 'choose', at: now(), action: 'skip' })
    else if (!aud.el.hidden) leaveAuditorium()
  },
  blocked: () => office.isOpen || sheet.isOpen || app.noPrintEl !== null,
  onPlayerKey(e) {
    if (!aud.el.hidden) aud.handleKey(e)
  },
})
installDrop((files) => void onFiles(files), lite.setDragging)
installLaunchQueue((files) => void onFiles(files))

renderStrips()
layers()
void restore()
afterPaint(() => {
  void capability()
  void loadOffsets()
})
