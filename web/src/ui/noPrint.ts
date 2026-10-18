// The No Print card (§4.6): names the EXACT missing decoder in one sentence and offers exactly
// two actions — the native builds, or another film. (A WebCodecs path was never wired to a
// demuxer, so it is not offered.) Nothing on this card uses --danger as a background.
import type { NoPrintReason } from '../engine/capability'
import { h } from './dom'

export interface NoPrintOptions {
  reason: NoPrintReason
  releasesUrl: string
  onOpenAnother(): void
}

export function noPrint(o: NoPrintOptions): HTMLElement {
  const another = h('button', { class: 'btn btn--ghost', type: 'button' }, 'Open another film')
  another.addEventListener('click', o.onOpenAnother)
  const actions = h(
    'div',
    { class: 'noprint__actions' },
    h(
      'a',
      { class: 'btn', href: o.releasesUrl, rel: 'noopener' },
      'Open in Marquee for Windows / Android',
    ),
    another,
  )
  return h(
    'section',
    { class: 'overlay noprint', 'aria-labelledby': 'noprint-title' },
    h('div', { class: 'beam beam--pin', 'aria-hidden': 'true' }),
    h(
      'div',
      {
        class: 'noprint__card',
        role: 'alertdialog',
        'aria-modal': 'true',
        'aria-labelledby': 'noprint-title',
        'aria-describedby': 'noprint-why',
      },
      h('p', { class: 'label' }, 'REEL 01 · THREADING'),
      h(
        'h2',
        { class: 'noprint__title', id: 'noprint-title' },
        "This print can't be projected here.",
      ),
      o.reason.tags ? h('p', { class: 'noprint__tags mono' }, o.reason.tags) : null,
      h('p', { class: 'sentence', id: 'noprint-why' }, o.reason.sentence),
      h(
        'p',
        { class: 'sentence sentence--muted' },
        'The Windows and Android apps play every format, with the same subtitles.',
      ),
      actions,
    ),
  )
}
