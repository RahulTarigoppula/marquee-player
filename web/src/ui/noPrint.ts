// The No Print card (§4.6): names the EXACT missing decoder in one sentence and offers exactly
// two actions. When window.VideoDecoder is undefined the WebCodecs button is ABSENT from the
// DOM — not merely hidden. Nothing on this card uses --danger as a background.
import type { NoPrintReason } from '../engine/capability'
import { h } from './dom'

export interface NoPrintOptions {
  reason: NoPrintReason
  webCodecsAvailable: boolean
  releasesUrl: string
  onWebCodecs(): void
  onOpenAnother(): void
}

export function noPrint(o: NoPrintOptions): HTMLElement {
  const actions = h('div', { class: 'noprint__actions' })
  if (o.webCodecsAvailable) {
    const wc = h('button', { class: 'btn', type: 'button' }, 'Try the WebCodecs path')
    wc.addEventListener('click', o.onWebCodecs)
    actions.append(wc)
  }
  actions.append(
    h(
      'a',
      {
        class: o.webCodecsAvailable ? 'btn btn--ghost' : 'btn',
        href: o.releasesUrl,
        rel: 'noopener',
      },
      'Open in Marquee for Windows / Android',
    ),
  )
  if (!o.webCodecsAvailable) {
    const another = h('button', { class: 'btn btn--ghost', type: 'button' }, 'Open another film')
    another.addEventListener('click', o.onOpenAnother)
    actions.append(another)
  }
  return h(
    'section',
    { class: 'overlay noprint', 'aria-labelledby': 'noprint-title' },
    h('div', { class: 'beam beam--pin', 'aria-hidden': 'true' }),
    h(
      'div',
      {
        class: 'noprint__card',
        role: 'alertdialog',
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
      h('p', { class: 'sentence', role: 'status', 'data-webcodecs-note': true }),
      actions,
    ),
  )
}
