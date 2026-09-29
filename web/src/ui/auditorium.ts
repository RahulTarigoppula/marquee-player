// The auditorium (§4.3): the picture on #000, walls around it (never chrome over it), the
// folio, aisle lights, the film gate and the transport. Chrome hides after 2400 ms idle; the
// folio survives at 40 %. The keyboard map mirrors §4.3 where it makes sense in a browser.
import type { StepKey } from '../engine/syncRule'
import { auditoriumFolio, withSuffixes } from '../engine/timecode'
import { h, ICONS, icon } from './dom'
import { filmGate } from './gate'

export const CONTROLS_IDLE_MS = 2400
const SKIP_S = 10
const ARROW_S = 5
const SHIFT_ARROW_S = 30
const VOLUME_STEP = 0.1
const SPEED_STEP = 0.25
const FRAME_S = 1 / 24
const AISLE_BULBS = 15

export const CUES: ReadonlyArray<readonly [string, string]> = [
  ['Space', 'Play / pause'],
  ['← / →', '∓5 s'],
  ['Shift + ← / →', '∓30 s'],
  ['↑ / ↓', 'Volume'],
  ['J / K', 'Sync ∓50 ms (Shift = 500 ms)'],
  ['Shift + J + K', 'Reset sync'],
  [', / .', 'Frame step'],
  ['[ / ]', 'Speed'],
  ['L', 'A–B loop'],
  ['F', 'Fullscreen'],
  ['P', 'Picture-in-picture'],
  ['S', 'Subtitle booth'],
  ['?', 'Cue sheet'],
  ['Esc', 'Back one lighting state'],
]

export interface AuditoriumOptions {
  onBack(): void
  onBooth(): void
  onSyncStep(k: StepKey): void
  onSyncReset(): void
}

export interface AuditoriumView {
  el: HTMLElement
  video: HTMLVideoElement
  pic: HTMLElement
  setTitle(title: string | null): void
  setSubDelay(v: number): void
  setHasSubs(on: boolean): void
  revealControls(): void
  /** Returns true when the key was handled. */
  handleKey(e: KeyboardEvent): boolean
  closeCueSheet(): boolean
}

export function auditorium(o: AuditoriumOptions): AuditoriumView {
  const video = h('video', { playsinline: true, preload: 'metadata', 'aria-label': 'The picture' })
  const pic = h('div', { class: 'pic' }, video)
  const folioText = h('span', {})
  const folio = h('header', { class: 'folio' }, folioText)
  const gate = filmGate((t) => {
    video.currentTime = t
  })

  const playIcon = () => icon(...(video.paused ? ICONS.play : ICONS.pause))
  const play = h(
    'button',
    { class: 'mark mark--play', type: 'button', 'aria-label': 'Play' },
    playIcon(),
  )
  const back10 = h(
    'button',
    { class: 'mark', type: 'button', 'aria-label': 'Back 10 seconds' },
    '◀10',
  )
  const fwd10 = h(
    'button',
    { class: 'mark', type: 'button', 'aria-label': 'Forward 10 seconds' },
    '10▶',
  )
  const syncBtn = h(
    'button',
    { class: 'sync', type: 'button', 'aria-label': 'Subtitle delay — open the booth' },
    'SYNC +0.00',
  )
  const cc = h(
    'button',
    { class: 'mark', type: 'button', 'aria-label': 'Subtitle booth', 'aria-pressed': 'false' },
    icon(...ICONS.captions),
  )
  const fs = h(
    'button',
    { class: 'mark', type: 'button', 'aria-label': 'Fullscreen' },
    icon(...ICONS.maximize),
  )
  const pip = h(
    'button',
    { class: 'mark', type: 'button', 'aria-label': 'Picture-in-picture' },
    icon(...ICONS.pip),
  )
  const cueBtn = h(
    'button',
    { class: 'mark cue-mark', type: 'button', 'aria-label': 'Cue sheet' },
    '?',
  )
  const exit = h(
    'button',
    { class: 'mark', type: 'button', 'aria-label': 'Leave the auditorium' },
    icon(...ICONS.back),
  )

  const controls = h(
    'div',
    { class: 'controls' },
    gate.el,
    h(
      'div',
      { class: 'transport' },
      exit,
      back10,
      play,
      fwd10,
      syncBtn,
      h('span', { class: 'spacer' }),
      cc,
      pip,
      fs,
      cueBtn,
    ),
  )
  const cuesheet = h(
    'div',
    { class: 'cuesheet', hidden: true, role: 'dialog', 'aria-label': 'Cue sheet — keyboard' },
    h(
      'div',
      {},
      h('span', { class: 'label' }, 'Cue sheet · keyboard'),
      h(
        'div',
        { class: 'cuegrid' },
        ...CUES.map(([k, v]) => h('div', {}, h('kbd', {}, k), h('span', {}, v))),
      ),
      h('p', { class: 'sentence' }, 'Esc always goes one lighting state up.'),
    ),
  )
  const el = h(
    'section',
    { class: 'overlay auditorium', 'aria-label': 'Auditorium', hidden: true },
    h('div', { class: 'wall wall--l', 'aria-hidden': 'true' }),
    h('div', { class: 'wall wall--r', 'aria-hidden': 'true' }),
    h('div', { class: 'wall wall--t', 'aria-hidden': 'true' }),
    folio,
    h('div', { class: 'picarea' }, pic),
    h(
      'div',
      { class: 'aisle', 'aria-hidden': 'true' },
      ...Array.from({ length: AISLE_BULBS }, () => h('i', { class: 'bulb' })),
    ),
    controls,
    cuesheet,
  )

  let title: string | null = null
  let delay = 0
  let loop: { a: number; b: number | null } | null = null
  let hideTimer: ReturnType<typeof setTimeout> | undefined
  const held = new Set<string>()

  const renderFolio = () => {
    const dur = Number.isFinite(video.duration) ? video.duration : null
    folioText.textContent = withSuffixes(auditoriumFolio(title, video.currentTime, dur), {
      speed: video.playbackRate,
      looping: loop?.b != null,
      subDelay: delay,
    })
    const buffered = video.buffered.length > 0 ? video.buffered.end(video.buffered.length - 1) : 0
    gate.update(video.currentTime, video.duration, buffered, video.readyState < 3 && !video.paused)
  }
  const reveal = () => {
    controls.classList.remove('is-hidden')
    folio.classList.remove('is-dim')
    el.classList.remove('is-idle')
    clearTimeout(hideTimer)
    hideTimer = setTimeout(() => {
      if (video.paused || el.hidden) return
      controls.classList.add('is-hidden')
      folio.classList.add('is-dim') // the folio survives at 40 %
      el.classList.add('is-idle')
    }, CONTROLS_IDLE_MS)
  }
  const toggle = () => (video.paused ? void video.play().catch(() => undefined) : video.pause())
  const seekBy = (s: number) => {
    video.currentTime = Math.max(0, Math.min(video.duration || 0, video.currentTime + s))
  }
  const fullscreen = () => {
    if (document.fullscreenElement) void document.exitFullscreen()
    else void el.requestFullscreen?.().catch(() => undefined)
  }
  const pictureInPicture = () => {
    if (document.pictureInPictureElement) void document.exitPictureInPicture()
    else void video.requestPictureInPicture?.().catch(() => undefined)
  }
  const toggleLoop = () => {
    if (!loop) loop = { a: video.currentTime, b: null }
    else if (loop.b === null) loop.b = Math.max(loop.a + 0.5, video.currentTime)
    else loop = null
    renderFolio()
  }

  for (const ev of [
    'timeupdate',
    'durationchange',
    'progress',
    'ratechange',
    'waiting',
    'playing',
    'seeked',
  ] as const) {
    video.addEventListener(ev, renderFolio)
  }
  video.addEventListener('timeupdate', () => {
    if (loop?.b != null && video.currentTime >= loop.b) video.currentTime = loop.a
  })
  const onPlayState = () => {
    play.replaceChildren(playIcon())
    play.setAttribute('aria-label', video.paused ? 'Play' : 'Pause')
    reveal()
  }
  video.addEventListener('play', onPlayState)
  video.addEventListener('pause', onPlayState)
  video.addEventListener('click', toggle)
  play.addEventListener('click', toggle)
  back10.addEventListener('click', () => seekBy(-SKIP_S))
  fwd10.addEventListener('click', () => seekBy(SKIP_S))
  syncBtn.addEventListener('click', o.onBooth)
  cc.addEventListener('click', o.onBooth)
  fs.addEventListener('click', fullscreen)
  pip.addEventListener('click', pictureInPicture)
  cueBtn.addEventListener('click', () => {
    cuesheet.hidden = false
  })
  exit.addEventListener('click', o.onBack)
  el.addEventListener('pointermove', reveal)
  el.addEventListener('focusin', reveal)

  // Long-press the SYNC readout to reset it.
  let press: ReturnType<typeof setTimeout> | undefined
  syncBtn.addEventListener('pointerdown', () => {
    press = setTimeout(o.onSyncReset, 600)
  })
  for (const ev of ['pointerup', 'pointerleave', 'pointercancel'] as const) {
    syncBtn.addEventListener(ev, () => clearTimeout(press))
  }
  document.addEventListener('keyup', (e) => held.delete(e.key.toLowerCase()))

  return {
    el,
    video,
    pic,
    setTitle(t) {
      title = t
      renderFolio()
    },
    setSubDelay(v) {
      delay = v
      syncBtn.textContent = `SYNC ${v < 0 ? '−' : '+'}${Math.abs(v).toFixed(2)}`
      renderFolio()
    },
    setHasSubs(on) {
      cc.classList.toggle('is-on', on)
    },
    revealControls: reveal,
    closeCueSheet() {
      if (cuesheet.hidden) return false
      cuesheet.hidden = true
      return true
    },
    handleKey(e) {
      const k = e.key.toLowerCase()
      held.add(k)
      reveal()
      if (e.key === ' ' && !(e.target instanceof HTMLButtonElement)) toggle()
      else if (e.key === 'ArrowLeft') seekBy(e.shiftKey ? -SHIFT_ARROW_S : -ARROW_S)
      else if (e.key === 'ArrowRight') seekBy(e.shiftKey ? SHIFT_ARROW_S : ARROW_S)
      else if (e.key === 'ArrowUp') video.volume = Math.min(1, video.volume + VOLUME_STEP)
      else if (e.key === 'ArrowDown') video.volume = Math.max(0, video.volume - VOLUME_STEP)
      else if (k === 'j' || k === 'k') {
        if (e.shiftKey && held.has('j') && held.has('k')) o.onSyncReset()
        else o.onSyncStep({ isK: k === 'k', shift: e.shiftKey })
      } else if (e.key === ',' || e.key === '.') {
        video.pause()
        seekBy(e.key === ',' ? -FRAME_S : FRAME_S)
      } else if (e.key === '[' || e.key === ']') {
        const r = video.playbackRate + (e.key === ']' ? SPEED_STEP : -SPEED_STEP)
        video.playbackRate = Math.max(0.25, Math.min(4, r))
      } else if (k === 'l') toggleLoop()
      else if (k === 'f') fullscreen()
      else if (k === 'p') pictureInPicture()
      else if (k === 's') o.onBooth()
      else if (e.key === '?') cuesheet.hidden = !cuesheet.hidden
      else return false
      e.preventDefault()
      return true
    },
  }
}
