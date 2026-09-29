// The Marquee Lite landing (§4.6): a lit sign, the idle beam, a sky that knows the time, a
// keyboard-operable drop frame backed by a REAL <input type="file">, and an honest,
// computed capability line.
import type { Capability } from '../engine/types'
import { h } from './dom'

export type Sky = 'dawn' | 'day' | 'dusk' | 'night'

/** The sky band follows the local clock (injected, so tests pin 21:14 IST = night). */
export function skyFor(now: Date): Sky {
  const hr = now.getHours()
  if (hr >= 5 && hr < 8) return 'dawn'
  if (hr >= 8 && hr < 17) return 'day'
  if (hr >= 17 && hr < 20) return 'dusk'
  return 'night'
}

const SIGN = 'MARQUEE LITE'
const BULBS_PER_ROW = 23
const WARMUP_CAP = 24 // letters; 60 ms stagger → at most 1.44 s

const bulbRow = () =>
  h(
    'div',
    { class: 'bulbrow', 'aria-hidden': 'true' },
    ...Array.from({ length: BULBS_PER_ROW }, () => h('i', { class: 'bulb' })),
  )

export interface LiteOptions {
  now: Date
  releasesUrl: string
  onFile(file: File): void
  onOffice(): void
  strip: HTMLElement
}

export interface LiteView {
  el: HTMLElement
  input: HTMLInputElement
  setCapability(cap: Capability): void
  setSentence(text: string | null): void
}

export function liteLanding(o: LiteOptions): LiteView {
  const letters = [...SIGN].map((ch, i) =>
    h(
      'span',
      { class: i < WARMUP_CAP ? 'ltr warm' : 'ltr', style: `--i:${i}` },
      ch === ' ' ? ' ' : ch,
    ),
  )
  const sky = skyFor(o.now)
  const clock = `${String(o.now.getHours()).padStart(2, '0')}:${String(o.now.getMinutes()).padStart(2, '0')}`

  const sign = h(
    'header',
    { class: 'marqueebox' },
    bulbRow(),
    h(
      'h1',
      { class: 'marquee__title' },
      h('span', { class: 'sr' }, 'Marquee Lite'),
      h('span', { 'aria-hidden': 'true' }, ...letters),
    ),
    h(
      'p',
      { class: 'marquee__meta' },
      h('span', {}, `${sky} · ${clock}`),
      h('span', { 'aria-hidden': 'true' }, '·'),
      h('span', { class: 'now' }, 'The house is open'),
    ),
    bulbRow(),
  )

  const input = h('input', {
    type: 'file',
    class: 'sr',
    tabindex: -1,
    accept: 'video/*,audio/*,.mkv,.mk3d,.avi,.ts,.m2ts,.srt,.ass,.ssa',
    'aria-label': 'Choose a film file',
  })
  const capline = h('p', { class: 'capline', id: 'capline' })
  const doors = h(
    'div',
    {
      class: 'doors',
      role: 'button',
      tabindex: 0,
      'aria-label': 'Drop a film here, or press Enter to open one',
      'aria-describedby': 'capline',
    },
    h('span', { class: 'doors__head' }, 'Drop a film here'),
    h('span', {}, 'or'),
    h('span', { class: 'disc', 'aria-hidden': 'true' }, 'Open'),
  )
  const sentence = h('p', { class: 'lite__sentence', role: 'status', hidden: true })

  const office = h('button', { class: 'linkbtn', type: 'button' }, 'Ticket office · sign in')
  office.addEventListener('click', o.onOffice)

  const el = h(
    'main',
    { class: 'lite', id: 'lite' },
    sign,
    doors,
    input,
    sentence,
    capline,
    h(
      'nav',
      { class: 'lite__links', 'aria-label': 'Elsewhere' },
      h(
        'a',
        { class: 'linkbtn', href: o.releasesUrl, rel: 'noopener' },
        'Open in Marquee for Windows / Android →',
      ),
      office,
    ),
    o.strip,
    h(
      'p',
      { class: 'attrib' },
      'Subtitles by OpenSubtitles.com · Fonts: Big Shoulders Display, Geist (OFL 1.1) · MIT. Nothing you open leaves this device except its 16-digit fingerprint.',
    ),
  )

  const open = () => input.click()
  doors.addEventListener('click', open)
  doors.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault()
      open()
    }
  })
  input.addEventListener('change', () => {
    const f = input.files?.[0]
    if (f) o.onFile(f)
    input.value = ''
  })
  const over = (on: boolean) => (e: DragEvent) => {
    e.preventDefault()
    doors.classList.toggle('is-over', on)
  }
  el.addEventListener('dragover', over(true))
  el.addEventListener('dragleave', over(false))
  el.addEventListener('drop', (e) => {
    over(false)(e)
    const f = e.dataTransfer?.files[0]
    if (f) o.onFile(f)
  })

  return {
    el,
    input,
    setCapability(cap) {
      capline.replaceChildren('This browser can play: ', h('span', { class: 'mono' }, cap.line))
    },
    setSentence(text) {
      sentence.hidden = text === null
      sentence.textContent = text ?? ''
    },
  }
}
