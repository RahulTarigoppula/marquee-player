// Marquee Lite â€” wiring. One AppState, DOM updates by CSS custom properties and textContent,
// three overlays toggled with `hidden`. The ritual:
//   drop â†’ capability probe â†’ moviehash â†’ IndexedDB (a hit costs ZERO requests) â†’ search â†’
//   score â†’ auto-pick â†’ download (signed in, via the Worker) â†’ subtitle-file â†’ SRTâ†’VTT â†’
//   <track> via a Blob URL â†’ play.
import './styles/tokens.css'
import './styles/app.css'
import { API_BASE, releasesUrl } from './config'
import { candidatesFromSearch, createApi, hashSearchParams, nameSearchParams } from './engine/api'
import { noPrintReason, probeCapability, sniffPrint } from './engine/capability'
import { isSubtitleName, parseName, parsePath } from './engine/filename'
import { HashUnavailable, isFileTooSmall, osHash } from './engine/osHash'
import { rank } from './engine/scoring'
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
} from './engine/types'
import * as idb from './storage/idb'
import type { AssTrack } from './ui/ass'
import { auditorium } from './ui/auditorium'
import { booth, CUE_SCALE } from './ui/booth'
import { h } from './ui/dom'
import { leader } from './ui/leader'
import { liteLanding, skyFor } from './ui/lite'
import { noPrint } from './ui/noPrint'
import { signIn } from './ui/signIn'
import { ticketStrip } from './ui/ticketStrip'

const PLAYABLE_WITHIN_MS = 5000
const SNIFF_BYTES = 1 << 20
const RESYNC_DEBOUNCE_MS = 120
const root = document.documentElement
const now = () => performance.now()

// â”€â”€ state â”€â”€
const app = {
  session: {
    jwt: null,
    jwtExpiresAt: null,
    quota: ANONYMOUS,
    languages: ['en'],
    preferHearingImpaired: false,
  } as LiteSession,
  user: null as string | null,
  sessionOnly: false,
  machine: initial({ subdlEnabled: false, language: 'en' }, ANONYMOUS) as Machine,
  sentence: null as string | null, // the Worker's own sentence for the current stall
  capability: null as Capability | null,
  file: null as File | null,
  parsed: null as ParsedName | null,
  hash: null as MovieHash | null,
  printOk: null as boolean | null,
  cues: null as Cue[] | null,
  ass: null as AssTrack | null,
  inSync: false,
  delay: 0,
  pendingTear: false,
  controller: new AbortController(),
  trackUrl: null as string | null,
  videoUrl: null as string | null,
  noPrintEl: null as HTMLElement | null,
}
const offsets = new OffsetBook()
// With no Worker configured (VITE_API_BASE empty) the site still plays films; subtitle search
// answers with one honest sentence instead of a network error.
const notConfigured = (): Promise<Response> =>
  Promise.resolve(
    new Response(
      JSON.stringify({
        error: 'forbidden-origin',
        sentence: "Subtitle search isn't set up for this site yet — the film still plays.",
      }),
      { status: 403, headers: { 'Content-Type': 'application/json' } },
    ),
  )
const api = createApi({
  base: API_BASE,
  fetch: (u, i) => (API_BASE ? fetch(u, i) : notConfigured()),
  jwt: () => app.session.jwt,
})

// â”€â”€ views â”€â”€
const openOffice = () => office.open(app.user)
const strips = [ticketStrip(openOffice), ticketStrip(openOffice), ticketStrip()]
const [landingStrip, leaderStrip, officeStrip] = strips as [
  ReturnType<typeof ticketStrip>,
  ReturnType<typeof ticketStrip>,
  ReturnType<typeof ticketStrip>,
]

const lite = liteLanding({
  now: new Date(),
  releasesUrl: releasesUrl(location),
  onFile: (f) => void openFile(f),
  onOffice: openOffice,
  strip: landingStrip.el,
})
const lead = leader(
  {
    onChoose: (action) => dispatch({ type: 'choose', at: now(), action }),
    onPick: (candidate) => dispatch({ type: 'pick', at: now(), candidate }),
    onManual: (query) => dispatch({ type: 'manual-query', at: now(), query }),
  },
  leaderStrip.el,
)
const aud = auditorium({
  onBack: () => leaveAuditorium(),
  onBooth: () => openBooth(),
  onSyncStep: (k) => setDelay(syncStep(app.delay, k)),
  onSyncReset: () => setDelay(syncReset()),
})
const sheet = booth({
  onTrack: (id) => showTrack(id !== null),
  onSize: (s) => aud.pic.style.setProperty('--cue-size', `${CUE_SCALE[s]}em`),
  onSync: (v) => setDelay(v),
  onFindAnother: () => dispatch({ type: 'research', at: now() }),
  onPick: (candidate) => dispatch({ type: 'pick', at: now(), candidate }),
  onClose: () => closeBooth(),
})
const office = signIn(
  {
    onSubmit: (u, p, sessionOnly) => login(u, p, sessionOnly),
    onSignOut: () => void signOut(),
    onClose: () => office.close(),
  },
  officeStrip.el,
)

root.dataset.sky = skyFor(new Date())
document.body.append(
  h(
    'div',
    { class: 'room' },
    h('div', { class: 'sky', 'aria-hidden': 'true' }),
    h('div', { class: 'beam', 'aria-hidden': 'true' }),
    h('div', { class: 'grain', 'aria-hidden': 'true' }),
    lite.el,
  ),
  lead.el,
  aud.el,
  sheet.el,
  office.el,
)

// â”€â”€ rendering â”€â”€
function renderStrips(): void {
  const strip = stripModel(app.session.quota, { now: new Date(), pendingTear: app.pendingTear })
  const q = app.session.quota
  const stubs = (q.remaining ?? 0) + (app.pendingTear ? 1 : 0)
  for (const s of strips) s.render(strip, q.signedIn ? stubs : 0)
  sheet.setTickets(strip.text)
}

function render(): void {
  const s = app.machine.state
  const sentence = s.failure ? (app.sentence ?? FAILURE_SENTENCE[s.failure]) : null
  lead.render(app.machine, sentence)
  if (!aud.el.hidden) sheet.setCandidates(s.candidates, s.picked, sentence)
  renderStrips()
}

// â”€â”€ the machine driver â”€â”€
function dispatch(e: ThreadingEvent): void {
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
      enterAuditorium(effect.withSubtitles)
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

// â”€â”€ effects â”€â”€
async function openFile(file: File): Promise<void> {
  if (isSubtitleName(file.name)) {
    if (app.file && !aud.el.hidden) await attachSidecar(file)
    else lite.setSentence("That's a subtitle file â€” open the film first, then drop its subtitles.")
    return
  }
  teardown()
  lite.setSentence(null)
  app.file = file
  app.parsed = parsePath(file.name)
  app.hash = null
  app.printOk = null
  root.dataset.house = 'down' // the ONE tween: --house 1 â†’ 0 over 900 ms
  lead.setMeta(file.size)
  lead.el.hidden = false
  app.videoUrl = URL.createObjectURL(file)
  aud.video.src = app.videoUrl
  aud.video.load()
  dispatch({ type: 'open', at: now(), parsed: app.parsed, quota: app.session.quota })
  const ok = await playable(aud.video)
  if (app.file !== file) return
  app.printOk = ok
  if (!ok) await showNoPrint(file)
}

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
    video.addEventListener('loadedmetadata', onMeta)
    video.addEventListener('error', onError)
  })
}

async function doHash(): Promise<void> {
  const file = app.file
  if (!file) return
  let hash: MovieHash | null = null
  try {
    hash = await osHash(file)
  } catch (e) {
    // < 128 KiB or unreadable: SILENT â€” "3" completes and "2" searches by name.
    if (!isFileTooSmall(e) && !(e instanceof HashUnavailable)) throw e
  }
  if (app.file !== file) return
  app.hash = hash
  setDelay(offsets.recall(hash), false)
  const lang = app.session.languages[0] ?? 'en'
  const cached = hash ? await idb.subtitles.get(hash, lang).catch(() => undefined) : undefined
  if (cached) {
    // Rung 0b: re-attach from IndexedDB â€” zero requests, zero tickets, works offline.
    app.cues = parseSrt(cached.vttText)
    app.inSync = cached.syncedByHash
    applyTrack()
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
    app.sentence = 'That print was empty â€” pick another.'
    dispatch({ type: 'failed', at: now(), failure: 'no-results' })
    return
  }
  app.cues = cues
  app.inSync = sc.candidate.moviehashMatch
  applyTrack()
  if (app.hash) {
    const vttText = toVtt(cues)
    void idb.subtitles
      .put({
        hash: app.hash,
        language: sc.candidate.language,
        provider: sc.candidate.provider,
        release: sc.candidate.release,
        syncedByHash: sc.candidate.moviehashMatch,
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
  dispatch({
    type: 'attached',
    at: now(),
    inSync: sc.candidate.moviehashMatch,
    quota: app.session.quota,
  })
}

// â”€â”€ subtitles on the picture â”€â”€
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
    label: 'Marquee',
    src: app.trackUrl,
    default: true,
  })
  video.append(track)
  track.track.mode = 'showing'
  aud.setHasSubs(true)
  sheet.setTracks(
    [
      {
        id: 'marquee',
        label: `${lang.toUpperCase()} Â· Marquee`,
        status: app.inSync ? 'synced' : 'by-name',
      },
    ],
    'marquee',
  )
}

function showTrack(on: boolean): void {
  const t = aud.video.textTracks[0]
  if (t) t.mode = on ? 'showing' : 'disabled'
  aud.setHasSubs(on)
  sheet.setTracks(
    app.cues
      ? [{ id: 'marquee', label: 'Marquee', status: app.inSync ? 'synced' : 'by-name' }]
      : [],
    on && app.cues ? 'marquee' : null,
  )
}

async function attachSidecar(file: File): Promise<void> {
  const text = await file.text()
  if (/\.(ass|ssa)$/i.test(file.name)) {
    app.ass?.destroy()
    const { attachAss } = await import('./ui/ass')
    app.ass = await attachAss(aud.video, text)
    app.ass.setDelay(app.delay)
    aud.setHasSubs(true)
    return
  }
  app.cues = parseSrt(text)
  app.inSync = false
  applyTrack()
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

// â”€â”€ lighting states â”€â”€
function enterAuditorium(withSubtitles: boolean): void {
  if (app.printOk === false || !app.file) return
  lead.el.hidden = true
  if (!aud.el.hidden) return
  aud.el.hidden = false
  aud.setTitle(app.parsed?.title ?? app.file.name)
  aud.setHasSubs(withSubtitles)
  if (!withSubtitles) sheet.setTracks([], null)
  void aud.video.play().catch(() => undefined)
  aud.revealControls() // controls show once for 2400 ms
}

function leaveAuditorium(): void {
  closeBooth()
  teardown()
  aud.el.hidden = true
  lead.el.hidden = true
  root.dataset.house = 'up'
  lite.el.querySelector<HTMLElement>('.doors')?.focus()
}

function teardown(): void {
  app.controller.abort()
  app.controller = new AbortController()
  if (app.machine.state.phase !== 'idle' && app.machine.state.phase !== 'done') {
    app.machine = reduce(app.machine, { type: 'cancel', at: now() }).machine
  }
  aud.video.pause()
  aud.video.removeAttribute('src')
  for (const t of aud.video.querySelectorAll('track')) t.remove()
  if (app.videoUrl) URL.revokeObjectURL(app.videoUrl)
  if (app.trackUrl) URL.revokeObjectURL(app.trackUrl)
  app.videoUrl = null
  app.trackUrl = null
  app.cues = null
  app.ass?.destroy()
  app.ass = null
  app.file = null
  app.noPrintEl?.remove()
  app.noPrintEl = null
}

let wasPlaying = false
function openBooth(): void {
  wasPlaying = !aud.video.paused
  aud.video.pause() // booth glass only ever sits over a PAUSED frame
  render()
  sheet.open()
}
function closeBooth(): void {
  if (!sheet.isOpen) return
  sheet.close()
  if (wasPlaying) void aud.video.play().catch(() => undefined)
}

async function showNoPrint(file: File): Promise<void> {
  dispatch({ type: 'cancel', at: now() }) // no ticket is spent on a print we cannot show
  lead.el.hidden = true
  const head = new Uint8Array(await file.slice(0, SNIFF_BYTES).arrayBuffer())
  const cap = app.capability ?? (await probe())
  const card = noPrint({
    reason: noPrintReason(sniffPrint(head, file.name), cap),
    webCodecsAvailable: cap.webCodecsAvailable,
    releasesUrl: releasesUrl(location),
    onWebCodecs: () => {
      const note = card.querySelector('[data-webcodecs-note]')
      if (note)
        note.textContent =
          "This build's WebCodecs path can't demux this container yet â€” the native builds can."
    },
    onOpenAnother: () => {
      leaveAuditorium()
      lite.input.click()
    },
  })
  app.noPrintEl = card
  document.body.append(card)
  card.querySelector<HTMLElement>('.btn')?.focus()
}

// â”€â”€ the ticket office â”€â”€
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
  office.close()
  dispatch({ type: 'signed-in', at: now(), quota: app.session.quota })
  return null
}

async function signOut(): Promise<void> {
  app.session.jwt = null
  app.session.quota = ANONYMOUS
  app.user = null
  await persistSession()
  office.close()
  render()
}

const persistSession = () =>
  idb.saveSession(app.session, app.user, app.sessionOnly).catch(() => undefined)

// â”€â”€ startup â”€â”€
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
  const loaded = await idb.loadSession().catch(() => null)
  if (loaded) {
    app.session = { ...app.session, ...loaded.session }
    app.user = loaded.user
  }
  for (const o of await idb.offsets.all().catch(() => []))
    offsets.remember(o.hash, o.delayMs / 1000)
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

document.addEventListener('keydown', (e) => {
  if (e.defaultPrevented) return
  const typing = e.target instanceof HTMLInputElement
  if (e.key === 'Escape') {
    // Esc always goes exactly one lighting state up.
    if (office.isOpen) office.close()
    else if (aud.closeCueSheet()) return
    else if (sheet.isOpen) closeBooth()
    else if (app.noPrintEl) leaveAuditorium()
    else if (!lead.el.hidden) dispatch({ type: 'choose', at: now(), action: 'skip' })
    else if (!aud.el.hidden) leaveAuditorium()
    return
  }
  if (typing || office.isOpen) return
  if (!aud.el.hidden && !sheet.isOpen) aud.handleKey(e)
})

renderStrips()
void probe()
void restore()
