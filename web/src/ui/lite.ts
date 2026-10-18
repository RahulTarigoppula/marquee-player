// The Marquee Lite landing (§4.6): a lit sign, the idle beam, a sky that knows the time, a big
// keyboard-operable drop frame backed by a REAL <input type="file" multiple>, and an honest,
// computed capability line. What the subtitle story is depends on whether online search exists.
import { LANGUAGES } from '../engine/languages'
import type { Capability } from '../engine/types'
import { h, ICONS, icon } from './dom'

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

/** Films, plus the subtitle files that may come with them. */
export const ACCEPT =
  'video/*,audio/*,.mkv,.mk3d,.mka,.avi,.ts,.m2ts,.mov,.m4v,.srt,.vtt,.ass,.ssa,text/vtt,application/x-subrip'

const bulbRow = () =>
  h(
    'div',
    { class: 'bulbrow', 'aria-hidden': 'true' },
    ...Array.from({ length: BULBS_PER_ROW }, () => h('i', { class: 'bulb' })),
  )

export interface LiteOptions {
  now: Date
  releasesUrl: string
  /** A Worker is configured: subtitles are searched online (sign-in needed to download). */
  searchEnabled: boolean
  language: string
  onFiles(files: File[]): void
  onOffice(): void
  onLanguage(code: string): void
  strip: HTMLElement
}

export interface LiteView {
  el: HTMLElement
  input: HTMLInputElement
  setCapability(cap: Capability): void
  setSentence(text: string | null): void
  setDragging(on: boolean): void
  setLanguage(code: string): void
}

export function liteLanding(o: LiteOptions): LiteView {
  const letters = [...SIGN].map((ch, i) =>
    h(
      'span',
      { class: i < WARMUP_CAP ? 'ltr warm' : 'ltr', style: `--i:${i}` },
      ch === ' ' ? '\u00A0' : ch,
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
    multiple: true,
    accept: ACCEPT,
    'aria-label': 'Choose a film (and its subtitle file)',
  })
  const capline = h('p', { class: 'capline', id: 'capline' })
  const doors = h(
    'div',
    {
      class: 'doors',
      role: 'button',
      tabindex: 0,
      'aria-label': 'Drop a film here, or press Enter to open one',
      'aria-describedby': 'doors-hint capline',
    },
    h('span', { class: 'doors__icon', 'aria-hidden': 'true' }, icon(...ICONS.film)),
    h('span', { class: 'doors__head' }, 'Drop a film here'),
    h('span', { class: 'disc', 'aria-hidden': 'true' }, 'Open a film'),
    h(
      'span',
      { class: 'doors__hint', id: 'doors-hint' },
      'Got a subtitle file? Choose it together with the film, or drop both at once.',
    ),
  )
  const sentence = h('p', { class: 'lite__sentence', role: 'status', hidden: true })

  const lang = h(
    'select',
    { class: 'select', 'aria-label': 'Subtitle language' },
    ...LANGUAGES.map((l) => h('option', { value: l.code }, l.name)),
  )
  lang.value = o.language
  lang.addEventListener('change', () => o.onLanguage(lang.value))

  const native = h(
    'a',
    { class: 'linkbtn', href: o.releasesUrl, rel: 'noopener' },
    'Open in Marquee for Windows / Android →',
  )

  let subs: HTMLElement
  if (o.searchEnabled) {
    const office = h('button', { class: 'linkbtn', type: 'button' }, 'Ticket office · sign in')
    office.addEventListener('click', o.onOffice)
    subs = h(
      'section',
      { class: 'lite__card', 'aria-labelledby': 'subs-title' },
      h('h2', { class: 'label', id: 'subs-title' }, 'Subtitles'),
      h(
        'p',
        { class: 'sentence' },
        'Marquee finds subtitles for the film by itself. Downloading them needs a free OpenSubtitles account.',
      ),
      h('label', { class: 'langrow' }, h('span', {}, 'Language'), lang),
      h('div', { class: 'lite__links' }, office),
      o.strip,
    )
  } else {
    subs = h(
      'section',
      { class: 'lite__card', 'aria-labelledby': 'subs-title' },
      h('h2', { class: 'label', id: 'subs-title' }, 'Subtitles'),
      h(
        'p',
        { class: 'sentence' },
        'Bring your own .srt, .vtt or .ass file — add it with the film, or from the player. Online subtitle search needs the ',
        h('a', { href: o.releasesUrl, rel: 'noopener' }, 'Windows / Android app'),
        ' or a configured server.',
      ),
    )
  }

  const el = h(
    'main',
    { class: 'lite', id: 'lite' },
    sign,
    doors,
    input,
    sentence,
    capline,
    subs,
    h('nav', { class: 'lite__links', 'aria-label': 'Elsewhere' }, native),
    h(
      'p',
      { class: 'attrib' },
      o.searchEnabled
        ? 'Your film never leaves this device. To find its subtitles, Marquee sends OpenSubtitles its 16-digit fingerprint and the title and year from its file name. '
        : 'Your film and subtitle files never leave this device — nothing is uploaded. ',
      'Subtitles by OpenSubtitles.com · Fonts: Big Shoulders Display, Geist (OFL 1.1) · MIT.',
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
    const files = [...(input.files ?? [])]
    input.value = ''
    if (files.length > 0) o.onFiles(files)
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
    setDragging(on) {
      doors.classList.toggle('is-over', on)
      el.classList.toggle('is-dragging', on)
    },
    setLanguage(code) {
      lang.value = code
    },
  }
}
