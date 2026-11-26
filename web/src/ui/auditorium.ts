// The auditorium (§4.3), as a modern overlaid player: the picture on #000, a top gradient with
// the title and the way back, a bottom gradient with the seek bar and the transport. Chrome hides
// after 2400 ms of stillness while the film plays. Mouse: click = play/pause, double-click =
// fullscreen. Touch: tap = show/hide the controls, double-tap left/right third = ∓10 s.
import type { StepKey } from '../engine/syncRule'
import { auditoriumFolio, signed, withSuffixes } from '../engine/timecode'
import { h, ICONS, icon, setText, trapFocus } from './dom'
import { clock, filmGate } from './gate'

export const CONTROLS_IDLE_MS = 2400
const SKIP_S = 10
const ARROW_S = 5
const SHIFT_ARROW_S = 30
const VOLUME_STEP = 0.1
const SPEED_STEP = 0.25
const SPEEDS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2] as const
const FRAME_S = 1 / 24
const DOUBLE_TAP_MS = 300
const LONG_PRESS_MS = 600
const RESUME_NOTE_MS = 6000 // the CSS fade-out ends at the same moment
const LIFT_LINES = -4 // lines from the bottom while the controls show

/** The web cue sheet. Web-only keys (K, J/L, M, 0-9, G/H, B, C) differ from the native map. */
export const CUES: ReadonlyArray<readonly [string, string]> = [
  ['Space · K', 'Play / pause'],
  ['← / →', 'Back / forward 5 s'],
  ['J / L', 'Back / forward 10 s'],
  ['Shift + ← / →', 'Back / forward 30 s'],
  ['0 … 9', 'Jump to 0 % … 90 %'],
  ['↑ / ↓', 'Volume'],
  ['M', 'Mute'],
  ['F · double-click', 'Fullscreen'],
  ['C', 'Subtitles on / off'],
  ['S', 'Subtitle settings'],
  ['G / H', 'Subtitles 50 ms earlier / later (Shift = 500 ms)'],
  ['Shift + G + H', 'Reset subtitle sync'],
  [', / .', 'Frame step'],
  ['[ / ]', 'Slower / faster'],
  ['B', 'A-B loop'],
  ['P', 'Picture-in-picture'],
  ['?', 'This cue sheet'],
  ['Esc', 'Back one lighting state'],
]

export interface AuditoriumOptions {
  onBack(): void
  onBooth(): void
  onAddSubtitle(): void
  onToggleSubs(): void
  onSyncStep(k: StepKey): void
  onSyncReset(): void
  onVolume(volume: number, muted: boolean): void
}

export interface NoticeLink {
  href: string
  label: string
}

export interface AuditoriumView {
  el: HTMLElement
  video: HTMLVideoElement
  setTitle(title: string | null): void
  setSubDelay(v: number): void
  /** `available`: a subtitle is attached; `on`: it is showing. */
  setSubs(available: boolean, on: boolean): void
  /** The subtitle settings sheet is over the picture: the big play mark steps aside. */
  setBoothOpen(open: boolean): void
  /** The booth's S/M/L as a factor on the cue font size. */
  setCueScale(scale: number): void
  setVolume(volume: number, muted: boolean): void
  revealControls(): void
  focusPlay(): void
  /** Returns true when the key was handled. */
  handleKey(e: KeyboardEvent): boolean
  closeCueSheet(): boolean
  closeMenus(): boolean
  notice(text: string, link?: NoticeLink): () => void
  clearNotices(): void
  offerResume(at: number, onStartOver: () => void): void
}

interface WebkitDocument {
  webkitFullscreenElement?: Element | null
  webkitExitFullscreen?: () => void
}
interface WebkitElement {
  webkitRequestFullscreen?: () => void
}
interface WebkitVideo {
  webkitEnterFullscreen?: () => void
  webkitSupportsPresentationMode?: (mode: string) => boolean
  webkitSetPresentationMode?: (mode: string) => void
  webkitPresentationMode?: string
}
type Lockable = ScreenOrientation & { lock?: (o: string) => Promise<void>; unlock?: () => void }

const markBtn = (label: string, paths: readonly string[], extra = '') =>
  h(
    'button',
    { class: `mark ${extra}`.trim(), type: 'button', 'aria-label': label, title: label },
    icon(...paths),
  )

/** Call `fn` when the pointer stays down on `el` for LONG_PRESS_MS. */
function onLongPress(el: HTMLElement, fn: () => void): void {
  let press: ReturnType<typeof setTimeout> | undefined
  el.addEventListener('pointerdown', () => {
    clearTimeout(press)
    press = setTimeout(fn, LONG_PRESS_MS)
  })
  for (const ev of ['pointerup', 'pointerleave', 'pointercancel'] as const) {
    el.addEventListener(ev, () => clearTimeout(press))
  }
}

export function auditorium(o: AuditoriumOptions): AuditoriumView {
  const video = h('video', {
    playsinline: true,
    'webkit-playsinline': true,
    preload: 'metadata',
    'aria-label': 'The picture',
  })
  const pic = h('div', { class: 'pic' }, video)
  const wdoc = document as Document & WebkitDocument
  const wvideo = video as HTMLVideoElement & WebkitVideo

  // ── top bar ──
  const titleEl = h('h2', { class: 'player__title' })
  const folioEl = h('p', { class: 'player__folio mono' })
  const exit = markBtn('Leave the auditorium', ICONS.back, 'mark--back')
  const cueBtn = markBtn('Keyboard shortcuts (cue sheet)', ICONS.keyboard, 'cue-mark')
  const top = h(
    'header',
    { class: 'player__top' },
    exit,
    h('div', { class: 'player__heading' }, titleEl, folioEl),
    cueBtn,
  )

  // ── centre: the big play mark, the pulse and the double-tap ripples ──
  const bigPlay = h(
    'button',
    { class: 'bigplay', type: 'button', 'aria-label': 'Play', tabindex: -1 },
    icon(...ICONS.play),
  )
  const pulse = h('div', { class: 'pulse', 'aria-hidden': 'true' })
  const rippleL = h('div', { class: 'ripple ripple--l', 'aria-hidden': 'true' })
  const rippleR = h('div', { class: 'ripple ripple--r', 'aria-hidden': 'true' })
  const notices = h('div', { class: 'player__notices', role: 'status', 'aria-live': 'polite' })
  // "Resumed from 1:02:13" sits bottom-left, just above the seek bar, and fades by itself.
  const resumeBox = h('div', { class: 'player__resume', role: 'status', 'aria-live': 'polite' })

  // ── bottom bar ──
  const gate = filmGate((t) => {
    video.currentTime = t
  })
  const play = markBtn('Play', ICONS.play, 'mark--play')
  const back10 = markBtn('Back 10 seconds', ICONS.rewind, 'mark--skip')
  back10.append(h('span', { class: 'mark__n', 'aria-hidden': 'true' }, '10'))
  const fwd10 = markBtn('Forward 10 seconds', ICONS.forward, 'mark--skip')
  fwd10.append(h('span', { class: 'mark__n', 'aria-hidden': 'true' }, '10'))
  const mute = markBtn('Mute', ICONS.volume, 'mark--mute')
  const volume = h('input', {
    class: 'volume',
    type: 'range',
    min: 0,
    max: 1,
    step: 0.05,
    value: 1,
    'aria-label': 'Volume',
  })
  const time = h('span', { class: 'player__time mono' }, '0:00 / 0:00')
  const syncBtn = h(
    'button',
    {
      class: 'syncchip mono',
      type: 'button',
      'aria-label': 'Subtitle delay: open subtitle settings',
      hidden: true,
    },
    'SYNC +0.00',
  )
  const addSub = markBtn('Add subtitle file…', ICONS.filePlus)
  const cc = markBtn('Subtitles', ICONS.captions)
  cc.title = 'Subtitles on / off (C)'
  cc.setAttribute('aria-pressed', 'false')
  const subSettings = markBtn('Subtitle settings', ICONS.sliders)
  subSettings.title = 'Subtitle settings (S)'
  const speedBtn = h(
    'button',
    {
      class: 'mark mark--speed mono',
      type: 'button',
      'aria-label': 'Playback speed',
      'aria-haspopup': 'true',
      'aria-expanded': 'false',
      title: 'Playback speed',
    },
    '1×',
  )
  const speedMenu = h(
    'div',
    { class: 'menu', role: 'menu', 'aria-label': 'Playback speed', hidden: true },
    ...SPEEDS.map((s) =>
      h(
        'button',
        { class: 'menu__item mono', type: 'button', role: 'menuitemradio', 'data-speed': s },
        s === 1 ? 'Normal' : `${s}×`,
      ),
    ),
  )
  const pip = markBtn('Picture-in-picture', ICONS.pip)
  const fs = markBtn('Fullscreen', ICONS.maximize)
  const pipSupported =
    (document.pictureInPictureEnabled === true && !video.disablePictureInPicture) ||
    wvideo.webkitSupportsPresentationMode?.('picture-in-picture') === true
  if (!pipSupported) pip.hidden = true

  const bottom = h(
    'div',
    { class: 'player__bottom' },
    gate.el,
    h(
      'div',
      { class: 'transport' },
      play,
      back10,
      fwd10,
      h('div', { class: 'volgroup' }, mute, volume),
      time,
      h('span', { class: 'spacer' }),
      syncBtn,
      addSub,
      cc,
      subSettings,
      h('div', { class: 'menuwrap' }, speedBtn, speedMenu),
      pip,
      fs,
    ),
  )

  // ── the cue sheet ──
  const cueClose = markBtn('Close the cue sheet', ICONS.close)
  const cuesheet = h(
    'div',
    { class: 'cuesheet', hidden: true },
    h(
      'div',
      {
        class: 'cuesheet__card',
        role: 'dialog',
        'aria-modal': 'true',
        'aria-labelledby': 'cuesheet-title',
      },
      h(
        'div',
        { class: 'cuesheet__head' },
        h('h2', { class: 'label', id: 'cuesheet-title' }, 'Cue sheet · keyboard'),
        cueClose,
      ),
      h(
        'div',
        { class: 'cuegrid' },
        ...CUES.map(([k, v]) => h('div', {}, h('kbd', {}, k), h('span', {}, v))),
      ),
      h(
        'p',
        { class: 'sentence' },
        'On a phone: tap to show the controls, double-tap the left or right side to skip 10 s.',
      ),
    ),
  )

  const stage = h('div', { class: 'stage' }, pic, pulse, rippleL, rippleR)
  const el = h(
    'section',
    { class: 'overlay auditorium', 'aria-label': 'Auditorium', hidden: true },
    stage,
    h('div', { class: 'scrim scrim--top', 'aria-hidden': 'true' }),
    h('div', { class: 'scrim scrim--bottom', 'aria-hidden': 'true' }),
    top,
    bigPlay,
    notices,
    resumeBox,
    bottom,
    cuesheet,
  )

  let delay = 0
  let subsAvailable = false
  let loop: { a: number; b: number | null } | null = null
  let hideTimer: ReturnType<typeof setTimeout> | undefined
  let overChrome = false
  let releaseCue: (() => void) | null = null
  const held = new Set<string>()

  // ── rendering ──
  const bufferedAt = (t: number) => {
    const b = video.buffered
    for (let i = 0; i < b.length; i++) if (b.start(i) <= t + 0.5 && t <= b.end(i)) return b.end(i)
    return 0
  }
  // Runs on every timeupdate/progress (about 4 Hz while playing): every write is skipped when the
  // value is unchanged, so a steady frame costs no style or layout work.
  const renderTime = () => {
    const dur = Number.isFinite(video.duration) ? video.duration : null
    const pos = video.currentTime
    setText(
      folioEl,
      withSuffixes(auditoriumFolio(null, pos, dur), {
        speed: video.playbackRate,
        looping: loop?.b != null,
        subDelay: delay,
      }),
    )
    const hours = (dur ?? 0) >= 3600
    setText(time, `${clock(pos, hours)} / ${dur === null ? '-:--' : clock(dur, hours)}`)
    gate.update(pos, video.duration, bufferedAt(pos), video.readyState < 3 && !video.paused)
  }
  // Icons are swapped only when the state they show changes.
  let playShown: boolean | null = null
  const renderPlay = () => {
    const paused = video.paused
    el.classList.toggle('is-paused', paused)
    if (paused === playShown) return
    playShown = paused
    play.replaceChildren(icon(...(paused ? ICONS.play : ICONS.pause)))
    play.setAttribute('aria-label', paused ? 'Play' : 'Pause')
    play.title = paused ? 'Play (K)' : 'Pause (K)'
  }
  let volumeIcon: readonly string[] | null = null
  const renderVolume = () => {
    const v = video.muted ? 0 : video.volume
    const paths = v === 0 ? ICONS.volumeOff : v < 0.5 ? ICONS.volumeLow : ICONS.volume
    if (paths !== volumeIcon) {
      volumeIcon = paths
      mute.replaceChildren(icon(...paths))
    }
    mute.setAttribute('aria-label', video.muted ? 'Unmute' : 'Mute')
    mute.title = video.muted ? 'Unmute (M)' : 'Mute (M)'
    volume.value = String(v)
    volume.style.setProperty('--v', `${v * 100}%`)
  }
  const renderSpeed = () => {
    const r = video.playbackRate
    speedBtn.textContent = `${Number.isInteger(r) ? r : r.toFixed(2).replace(/0$/, '')}×`
    for (const b of speedMenu.querySelectorAll<HTMLElement>('[data-speed]'))
      b.setAttribute('aria-checked', Number(b.dataset.speed) === r ? 'true' : 'false')
  }

  // ── chrome visibility ──
  // While the bottom bar shows, subtitle cues step up a few lines so the bar never covers them;
  // when it hides they return to their own line. Cues with a line of their own (an8 → top) stay.
  // An ASS canvas has no cue lines, so CSS lifts the whole canvas instead (player.css).
  const lifted = new WeakSet<TextTrackCue>()
  let lift = false
  const applyLift = () => {
    if (typeof VTTCue === 'undefined') return
    for (const t of video.textTracks) {
      let changed = false
      for (const c of t.cues ?? []) {
        if (!(c instanceof VTTCue)) continue
        if (lift && c.line === 'auto') {
          c.line = LIFT_LINES
          lifted.add(c)
          changed = true
        } else if (!lift && lifted.has(c)) {
          c.line = 'auto'
          lifted.delete(c)
          changed = true
        }
      }
      // Browsers keep a cue that is already on screen where it was laid out; re-showing the
      // track makes them place it again at its new line.
      if (changed && t.mode === 'showing') {
        t.mode = 'hidden'
        t.mode = 'showing'
      }
    }
  }
  const setIdle = (idle: boolean) => {
    el.classList.toggle('is-idle', idle)
    if (lift === !idle) return
    lift = !idle
    applyLift()
  }
  // A re-emitted track (a sync change) loads its cues later: lift them as they arrive.
  video.addEventListener('load', applyLift, true)
  const menusOpen = () => !speedMenu.hidden || !cuesheet.hidden
  const hideSoon = () => {
    clearTimeout(hideTimer)
    hideTimer = setTimeout(() => {
      if (video.paused || el.hidden || overChrome || menusOpen()) return
      // A keyboard user tabbing along the bar keeps it lit; a mouse click's focus does not.
      const active = document.activeElement
      const keyboardOnBar =
        active instanceof HTMLElement &&
        (top.contains(active) || bottom.contains(active)) &&
        active.matches(':focus-visible')
      if (keyboardOnBar) return
      setIdle(true)
    }, CONTROLS_IDLE_MS)
  }
  const reveal = () => {
    setIdle(false)
    hideSoon()
  }
  const hideNow = () => {
    if (video.paused || menusOpen()) return
    clearTimeout(hideTimer)
    setIdle(true)
  }

  // ── actions ──
  const toggle = () => (video.paused ? void video.play().catch(() => undefined) : video.pause())
  const pulseIcon = (paths: readonly string[]) => {
    pulse.replaceChildren(icon(...paths))
    pulse.classList.remove('is-on')
    void pulse.offsetWidth // restart the animation
    pulse.classList.add('is-on')
  }
  const seekTo = (t: number) => {
    video.currentTime = Math.max(0, Math.min(video.duration || 0, t))
  }
  const seekBy = (s: number) => seekTo(video.currentTime + s)
  const ripple = (dir: -1 | 1, total: number) => {
    const r = dir < 0 ? rippleL : rippleR
    r.textContent = `${dir < 0 ? '−' : '+'}${total} s`
    r.classList.remove('is-on')
    void r.offsetWidth
    r.classList.add('is-on')
  }
  const setVol = (v: number, muted = video.muted) => {
    video.volume = Math.max(0, Math.min(1, v))
    video.muted = muted
    o.onVolume(video.volume, video.muted)
  }
  const fullscreenEl = () => document.fullscreenElement ?? wdoc.webkitFullscreenElement ?? null
  const fullscreen = () => {
    if (fullscreenEl()) {
      if (document.exitFullscreen) void document.exitFullscreen().catch(() => undefined)
      else wdoc.webkitExitFullscreen?.()
      return
    }
    const wel = el as HTMLElement & WebkitElement
    if (el.requestFullscreen) {
      void el
        .requestFullscreen({ navigationUI: 'hide' })
        .then(lockLandscape)
        .catch(() => undefined)
    } else if (wel.webkitRequestFullscreen) wel.webkitRequestFullscreen()
    else wvideo.webkitEnterFullscreen?.() // iPhone: only the <video> itself can go fullscreen
  }
  const lockLandscape = () => {
    const orientation = screen.orientation as Lockable | undefined
    const coarse = matchMedia('(pointer: coarse)').matches
    if (!coarse || !orientation?.lock || video.videoWidth < video.videoHeight) return
    void orientation.lock('landscape').catch(() => undefined)
  }
  const onFullscreenChange = () => {
    const on = fullscreenEl() !== null
    fs.replaceChildren(icon(...(on ? ICONS.minimize : ICONS.maximize)))
    fs.setAttribute('aria-label', on ? 'Exit fullscreen' : 'Fullscreen')
    fs.title = on ? 'Exit fullscreen (F)' : 'Fullscreen (F)'
    if (!on) (screen.orientation as Lockable | undefined)?.unlock?.()
  }
  document.addEventListener('fullscreenchange', onFullscreenChange)
  document.addEventListener('webkitfullscreenchange', onFullscreenChange)
  const pictureInPicture = () => {
    if (!pipSupported) return
    if (document.pictureInPictureElement) void document.exitPictureInPicture()
    else if (video.requestPictureInPicture)
      void video.requestPictureInPicture().catch(() => undefined)
    else
      wvideo.webkitSetPresentationMode?.(
        wvideo.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture',
      )
  }
  const toggleLoop = () => {
    if (!loop) loop = { a: video.currentTime, b: null }
    else if (loop.b === null) loop.b = Math.max(loop.a + 0.5, video.currentTime)
    else loop = null
    renderTime()
  }
  const openSpeed = (on: boolean) => {
    speedMenu.hidden = !on
    speedBtn.setAttribute('aria-expanded', on ? 'true' : 'false')
    if (on) {
      renderSpeed()
      speedMenu.querySelector<HTMLElement>('[aria-checked="true"]')?.focus()
    }
    reveal()
  }
  const openCueSheet = () => {
    if (!cuesheet.hidden) return
    cuesheet.hidden = false
    releaseCue = trapFocus(cuesheet)
    cueClose.focus()
  }
  const closeCueSheet = () => {
    if (cuesheet.hidden) return false
    cuesheet.hidden = true
    releaseCue?.()
    releaseCue = null
    return true
  }

  // ── wiring ──
  for (const ev of [
    'timeupdate',
    'durationchange',
    'progress',
    'ratechange',
    'waiting',
    'playing',
    'seeked',
    'loadedmetadata',
  ] as const) {
    video.addEventListener(ev, renderTime)
  }
  video.addEventListener('ratechange', renderSpeed)
  video.addEventListener('volumechange', renderVolume)
  const onPlayState = () => {
    renderPlay()
    reveal()
  }
  video.addEventListener('play', onPlayState)
  video.addEventListener('pause', onPlayState)
  video.addEventListener('ended', onPlayState)

  // Taps and clicks on the picture.
  let lastTap = { at: 0, x: 0, chain: 0, dir: 0 as -1 | 0 | 1 }
  let singleTap: ReturnType<typeof setTimeout> | undefined
  stage.addEventListener('pointerup', (e) => {
    if (e.button > 0) return
    const now = performance.now()
    const r = stage.getBoundingClientRect()
    const third = (e.clientX - r.left) / (r.width || 1)
    const dir: -1 | 0 | 1 = third < 1 / 3 ? -1 : third > 2 / 3 ? 1 : 0
    const double = now - lastTap.at < DOUBLE_TAP_MS && Math.abs(e.clientX - lastTap.x) < 120
    if (e.pointerType === 'mouse') {
      toggle()
      pulseIcon(video.paused ? ICONS.pause : ICONS.play)
      if (double) {
        fullscreen()
        lastTap = { at: 0, x: 0, chain: 0, dir: 0 }
      } else lastTap = { at: now, x: e.clientX, chain: 0, dir: 0 }
      reveal()
      return
    }
    // Touch / pen: a tap toggles the controls; a double-tap on a side skips (and keeps skipping
    // while the taps keep coming); a double-tap in the middle goes fullscreen.
    if (double || (lastTap.chain > 0 && dir === lastTap.dir && now - lastTap.at < 700)) {
      clearTimeout(singleTap)
      if (dir === 0) {
        if (lastTap.chain === 0) fullscreen()
        lastTap = { at: 0, x: 0, chain: 0, dir: 0 }
        return
      }
      const chain = lastTap.dir === dir ? lastTap.chain + 1 : 1
      seekBy(dir * SKIP_S)
      ripple(dir, chain * SKIP_S)
      lastTap = { at: now, x: e.clientX, chain, dir }
      return
    }
    lastTap = { at: now, x: e.clientX, chain: 0, dir }
    clearTimeout(singleTap)
    singleTap = setTimeout(() => {
      if (el.classList.contains('is-idle') || video.paused) reveal()
      else hideNow()
    }, DOUBLE_TAP_MS)
  })
  // One passive listener for the whole auditorium (the stage's moves bubble here). A moving
  // mouse fires this up to once a frame, so it only re-arms the timer unless the chrome is hidden.
  el.addEventListener(
    'pointermove',
    (e) => {
      if (e.pointerType === 'mouse') reveal()
    },
    { passive: true },
  )
  for (const bar of [top, bottom]) {
    bar.addEventListener('pointerenter', (e) => {
      if (e.pointerType === 'mouse') overChrome = true
    })
    bar.addEventListener('pointerleave', () => {
      overChrome = false
      reveal()
    })
  }
  el.addEventListener('focusin', reveal)
  // A button pressed with the mouse or a finger gives its focus back, so Space and the arrows
  // keep meaning play/pause and seek instead of pressing that button again.
  el.addEventListener('click', (e) => {
    if (e.detail === 0) return // a keyboard press: keep the focus where the viewer put it
    const b = e.target instanceof Element ? e.target.closest('button') : null
    if (b && (top.contains(b) || bottom.contains(b)) && document.activeElement === b) b.blur()
  })

  bigPlay.addEventListener('click', () => {
    void video.play().catch(() => undefined)
  })
  play.addEventListener('click', toggle)
  back10.addEventListener('click', () => seekBy(-SKIP_S))
  fwd10.addEventListener('click', () => seekBy(SKIP_S))
  mute.addEventListener('click', () => {
    if (video.muted || video.volume === 0) setVol(video.volume === 0 ? 0.5 : video.volume, false)
    else setVol(video.volume, true)
  })
  volume.addEventListener('input', () => setVol(Number(volume.value), Number(volume.value) === 0))
  syncBtn.addEventListener('click', o.onBooth)
  subSettings.addEventListener('click', o.onBooth)
  addSub.addEventListener('click', o.onAddSubtitle)
  // The subtitles button switches them on and off (with none attached it asks for a file); a
  // long press opens the subtitle settings, for phones without an S key.
  let ccHeld = false
  cc.addEventListener('pointerdown', () => {
    ccHeld = false
  })
  cc.addEventListener('contextmenu', (e) => e.preventDefault())
  cc.addEventListener('click', () => {
    if (ccHeld) ccHeld = false
    else o.onToggleSubs()
  })
  onLongPress(cc, () => {
    ccHeld = true
    o.onBooth()
  })
  speedBtn.addEventListener('click', () => openSpeed(speedMenu.hidden))
  speedMenu.addEventListener('click', (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('[data-speed]')
    if (!b) return
    video.playbackRate = Number(b.dataset.speed)
    openSpeed(false)
    if (e.detail === 0) speedBtn.focus() // chosen from the keyboard: back to the menu button
  })
  speedMenu.addEventListener('keydown', (e) => {
    const items = [...speedMenu.querySelectorAll<HTMLElement>('[data-speed]')]
    const i = items.indexOf(document.activeElement as HTMLElement)
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      items[(i + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length]?.focus()
    } else if (e.key === 'Escape' || e.key === 'Tab') {
      openSpeed(false)
      speedBtn.focus()
      if (e.key === 'Tab') return
    } else return
    e.preventDefault()
    e.stopPropagation()
  })
  document.addEventListener('pointerdown', (e) => {
    if (
      !speedMenu.hidden &&
      !(e.target instanceof Node && speedMenu.parentElement?.contains(e.target))
    )
      openSpeed(false)
  })
  fs.addEventListener('click', fullscreen)
  pip.addEventListener('click', pictureInPicture)
  cueBtn.addEventListener('click', openCueSheet)
  cueClose.addEventListener('click', closeCueSheet)
  cuesheet.addEventListener('click', (e) => {
    if (e.target === cuesheet) closeCueSheet()
  })
  exit.addEventListener('click', o.onBack)

  // Long-press the SYNC readout to reset it.
  onLongPress(syncBtn, o.onSyncReset)
  document.addEventListener('keyup', (e) => held.delete(e.key.toLowerCase()))

  // ── Media Session: the lock screen, headset keys and the OS media flyout ──
  const ms = 'mediaSession' in navigator ? navigator.mediaSession : null
  let lastPos = 0
  const updatePosition = () => {
    if (!ms || Math.abs(video.currentTime - lastPos) < 1 || !Number.isFinite(video.duration)) return
    lastPos = video.currentTime
    try {
      ms.setPositionState({
        duration: video.duration,
        playbackRate: video.playbackRate,
        position: Math.min(video.currentTime, video.duration),
      })
    } catch {
      // not supported
    }
  }
  // One timeupdate listener for the A-B loop and the OS position.
  video.addEventListener('timeupdate', () => {
    if (loop?.b != null && video.currentTime >= loop.b) video.currentTime = loop.a
    updatePosition()
  })
  if (ms) {
    const on = (a: MediaSessionAction, fn: MediaSessionActionHandler) => {
      try {
        ms.setActionHandler(a, fn)
      } catch {
        // an action this browser does not know
      }
    }
    on('play', () => void video.play().catch(() => undefined))
    on('pause', () => video.pause())
    on('seekbackward', (d) => seekBy(-(d.seekOffset ?? SKIP_S)))
    on('seekforward', (d) => seekBy(d.seekOffset ?? SKIP_S))
    on('seekto', (d) => {
      if (d.seekTime !== undefined) seekTo(d.seekTime)
    })
  }

  // The SYNC chip shows only while the subtitles are shifted (the folio says SUB too).
  const renderSyncChip = () => {
    syncBtn.hidden = !subsAvailable || Math.round(delay * 100) === 0
  }

  renderPlay()
  renderVolume()
  renderSpeed()

  const view: AuditoriumView = {
    el,
    video,
    setTitle(t) {
      titleEl.textContent = t ?? ''
      if (ms) {
        ms.metadata =
          t === null || typeof MediaMetadata === 'undefined'
            ? null
            : new MediaMetadata({
                title: t,
                artist: 'Marquee Lite',
                artwork: [
                  {
                    src: `${import.meta.env.BASE_URL}icons/icon-512.png`,
                    sizes: '512x512',
                    type: 'image/png',
                  },
                ],
              })
      }
      renderTime()
    },
    setSubDelay(v) {
      delay = v
      syncBtn.textContent = `SYNC ${signed(v)}`
      renderSyncChip()
      renderTime()
    },
    setSubs(available, on) {
      subsAvailable = available
      cc.classList.toggle('is-on', available && on)
      cc.setAttribute('aria-pressed', available && on ? 'true' : 'false')
      renderSyncChip()
    },
    setBoothOpen(open) {
      el.classList.toggle('is-booth', open)
    },
    setCueScale(scale) {
      pic.style.setProperty('--cue-size', `${scale}em`)
      pic.style.setProperty('--cue-scale', String(scale))
    },
    setVolume(v, muted) {
      video.volume = v
      video.muted = muted
      renderVolume()
    },
    revealControls: reveal,
    focusPlay() {
      // No focus ring for a focus the viewer did not move themselves.
      play.focus({ preventScroll: true, focusVisible: false } as FocusOptions)
    },
    closeCueSheet,
    closeMenus() {
      if (speedMenu.hidden) return false
      openSpeed(false)
      speedBtn.focus()
      return true
    },
    notice(text, link) {
      const close = markBtn('Dismiss', ICONS.close, 'mark--sm')
      const n = h(
        'div',
        { class: 'notice' },
        h(
          'p',
          {},
          text,
          link ? ' ' : null,
          link ? h('a', { href: link.href, rel: 'noopener', target: '_blank' }, link.label) : null,
        ),
        close,
      )
      const remove = () => n.remove()
      close.addEventListener('click', remove)
      notices.append(n)
      return remove
    },
    clearNotices() {
      notices.replaceChildren()
      resumeBox.replaceChildren()
    },
    offerResume(at, onStartOver) {
      const again = h('button', { class: 'linkbtn', type: 'button' }, 'Start over')
      const n = h(
        'div',
        { class: 'notice notice--resume' },
        h('p', {}, `Resumed from ${clock(at)}`),
        again,
      )
      again.addEventListener('click', () => {
        onStartOver()
        n.remove()
      })
      resumeBox.replaceChildren(n)
      setTimeout(() => n.remove(), RESUME_NOTE_MS)
    },
    handleKey(e) {
      if (e.ctrlKey || e.metaKey || e.altKey) return false
      const k = e.key.toLowerCase()
      held.add(k)
      reveal()
      // Space presses a button only when the viewer tabbed to it; a button that merely kept the
      // focus from a click gives it up and Space plays or pauses.
      const t = e.target
      const onButton = t instanceof HTMLButtonElement && t.matches(':focus-visible')
      if (e.key === ' ' && !onButton && t instanceof HTMLButtonElement) t.blur()
      if (e.key === ' ' && !onButton) toggle()
      else if (k === 'k') toggle()
      else if (e.key === 'ArrowLeft') seekBy(e.shiftKey ? -SHIFT_ARROW_S : -ARROW_S)
      else if (e.key === 'ArrowRight') seekBy(e.shiftKey ? SHIFT_ARROW_S : ARROW_S)
      else if (k === 'j') seekBy(-SKIP_S)
      else if (k === 'l') seekBy(SKIP_S)
      else if (e.key === 'ArrowUp') setVol(video.volume + VOLUME_STEP, false)
      else if (e.key === 'ArrowDown') setVol(video.volume - VOLUME_STEP)
      else if (k === 'm') setVol(video.volume, !video.muted)
      else if (/^[0-9]$/.test(e.key) && !e.shiftKey)
        seekTo(((video.duration || 0) * Number(e.key)) / 10)
      else if (e.key === 'Home') seekTo(0)
      else if (e.key === 'End') seekTo(video.duration || 0)
      else if (k === 'g' || k === 'h') {
        if (e.shiftKey && held.has('g') && held.has('h')) o.onSyncReset()
        else if (subsAvailable) o.onSyncStep({ isK: k === 'h', shift: e.shiftKey })
      } else if (e.key === ',' || e.key === '.') {
        video.pause()
        seekBy(e.key === ',' ? -FRAME_S : FRAME_S)
      } else if (e.key === '[' || e.key === ']') {
        const r = video.playbackRate + (e.key === ']' ? SPEED_STEP : -SPEED_STEP)
        video.playbackRate = Math.max(0.25, Math.min(4, r))
      } else if (k === 'b') toggleLoop()
      else if (k === 'f') fullscreen()
      else if (k === 'p') pictureInPicture()
      else if (k === 'c') o.onToggleSubs()
      else if (k === 's') o.onBooth()
      else if (e.key === '?') {
        if (!closeCueSheet()) openCueSheet()
      } else return false
      e.preventDefault()
      return true
    },
  }
  return view
}
