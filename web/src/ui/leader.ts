// The academy leader (§3.6.2, §4.2). The sweep angle is the machine's sweep — driven by real
// promise progress, frozen on a stall. The phase is announced once per phase (aria-live),
// never per frame. Fallback rows slide in beneath the numeral without leaving the leader.
import type { Machine } from '../engine/threading'
import { numeral, phaseLabel } from '../engine/threading'
import { THREADING_FOLIO } from '../engine/timecode'
import type { NextAction, ScoredCandidate, ThreadingState } from '../engine/types'
import { fill, h } from './dom'

export const NEXT_LABEL: Readonly<Record<NextAction, string>> = {
  'filename-search': 'Search by the file name',
  subdl: 'Try the Subdl slot',
  manual: 'Type the title yourself',
  skip: 'Play without subtitles',
  'sign-in': 'Sign in at the ticket office (free)',
  retry: 'Try again',
  webcodecs: 'Try the WebCodecs path',
}

export interface LeaderCallbacks {
  onChoose(action: NextAction): void
  onPick(c: ScoredCandidate): void
  onManual(query: string): void
  /** Open the picker for a subtitle file from this device. */
  onSidecar(): void
}

export interface LeaderView {
  el: HTMLElement
  /** Move focus into the leader (it is a full-screen layer). */
  focus(): void
  render(m: Machine, sentence: string | null): void
  setMeta(sizeBytes: number | null): void
  showManual(): void
  flash(ms: number): Promise<void>
}

const thin = (n: number) => n.toLocaleString('en-US').replace(/,/g, ' ')

export function formatSize(bytes: number): string {
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(2)} GB`
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(1)} MB`
  return `${Math.round(bytes / 1e3)} KB`
}

/** One candidate row: language · MATCH bulb · release · downloads · fps · HI. */
export function candidateRow(
  sc: ScoredCandidate,
  picked: boolean,
  onPick: () => void,
): HTMLButtonElement {
  const c = sc.candidate
  const meta = [
    `${thin(c.downloadCount)} dl`,
    c.fps ? `${c.fps} fps` : null,
    c.hearingImpaired ? 'HI' : null,
  ]
    .filter(Boolean)
    .join(' · ')
  const right = c.moviehashMatch
    ? h('span', { class: 'oklabel' }, 'MATCH')
    : h('span', { class: 'warnlabel' }, 'BY NAME · CHECK SYNC')
  const row = h(
    'button',
    { class: 'row', type: 'button', role: 'radio', 'aria-checked': picked ? 'true' : 'false' },
    h(
      'span',
      { class: 'row__code' },
      c.language.toUpperCase(),
      c.moviehashMatch ? h('i', { class: 'bulb bulb--green', 'aria-hidden': 'true' }) : null,
    ),
    h(
      'span',
      {},
      h('span', { class: 'row__rel' }, c.release ?? 'Untitled print'),
      h(
        'span',
        { class: 'row__meta' },
        meta,
        c.machineTranslated || c.aiTranslated ? ' · machine-translated' : '',
      ),
    ),
    right,
  )
  row.addEventListener('click', onPick)
  return row
}

export function leader(cb: LeaderCallbacks, strip: HTMLElement): LeaderView {
  const sweep = h('div', { class: 'leader__sweep' })
  const hand = h('div', { class: 'leader__hand' })
  const num = h('div', { class: 'leader__num' })
  const dial = h(
    'div',
    { class: 'leader', 'aria-hidden': 'true' },
    sweep,
    h('div', { class: 'leader__ring leader__ring--a' }),
    h('div', { class: 'leader__ring leader__ring--b' }),
    h('div', { class: 'leader__cross' }),
    hand,
    num,
  )
  const phase = h('p', { class: 'phase', 'aria-live': 'polite' })
  const hashline = h('p', { class: 'hashline mono' })
  const rows = h('div', { class: 'rows', role: 'radiogroup', 'aria-label': 'Subtitle prints' })
  const sentence = h('p', { class: 'sentence', role: 'status' })
  const fallbacks = h('div', { class: 'fallbacks', role: 'group', 'aria-label': 'What next' })
  const query = h('input', {
    class: 'field',
    type: 'search',
    'aria-label': 'Film title',
    placeholder: 'The Third Man 1949',
  })
  const manual = h(
    'form',
    { class: 'searchwrap', hidden: true, role: 'search' },
    query,
    h('button', { class: 'btn', type: 'submit' }, 'Search'),
  )
  manual.addEventListener('submit', (e) => {
    e.preventDefault()
    const q = query.value.trim()
    if (q !== '') cb.onManual(q)
  })
  const skip = h('button', { class: 'linkbtn', type: 'button' }, 'Skip subtitles')
  const own = h(
    'button',
    { class: 'fallback fallback--own', type: 'button' },
    'Use a subtitle file from this device',
  )
  own.addEventListener('click', cb.onSidecar)
  skip.addEventListener('click', () => cb.onChoose('skip'))

  const el = h(
    'section',
    { class: 'overlay threading', 'aria-label': 'Threading', hidden: true },
    h('div', { class: 'beam', 'aria-hidden': 'true', style: '--beam-w: 52%' }),
    h('header', { class: 'folio' }, h('span', {}, THREADING_FOLIO), skip),
    h(
      'div',
      { class: 'thread__grid' },
      h('div', { class: 'leaderwrap' }, dial, phase, hashline),
      h(
        'div',
        { class: 'candidates' },
        h(
          'div',
          { class: 'candidates__head' },
          h('span', { class: 'label' }, 'Prints found · OpenSubtitles'),
        ),
        rows,
        sentence,
        manual,
        fallbacks,
      ),
    ),
    strip,
  )

  let size: number | null = null
  let lastPhase: ThreadingState['phase'] | null = null
  let lastRows: { list: ScoredCandidate[]; picked: ScoredCandidate | null } | null = null
  let lastNext = ''

  return {
    el,
    focus() {
      skip.focus({ preventScroll: true })
    },
    setMeta(bytes) {
      size = bytes
    },
    render(m, text) {
      const s = m.state
      num.textContent = numeral(s.phase)
      dial.style.setProperty('--a', `${(s.sweep * 360).toFixed(1)}deg`)
      dial.classList.toggle('is-stalled', s.failure !== null)
      if (s.phase !== lastPhase) {
        lastPhase = s.phase
        phase.textContent = phaseLabel(m) // announced once per phase
      }
      const parts: Array<Node | string> = []
      if (s.hash) parts.push(h('b', {}, s.hash))
      else if (s.phase === 'hashing') parts.push('················')
      if (size !== null) parts.push(...(parts.length > 0 ? [' · '] : []), formatSize(size))
      fill(hashline, ...parts)
      if (!lastRows || lastRows.list !== s.candidates || lastRows.picked !== s.picked) {
        lastRows = { list: s.candidates, picked: s.picked }
        fill(rows, ...s.candidates.map((c) => candidateRow(c, c === s.picked, () => cb.onPick(c))))
      }
      if (sentence.textContent !== (text ?? '')) sentence.textContent = text ?? ''
      const key = s.next.join('|')
      if (key !== lastNext) {
        lastNext = key
        const rows = s.next.map((a, i) => {
          const b = h(
            'button',
            {
              class: a === 'skip' && s.failure === 'offline' ? 'fallback is-lit' : 'fallback',
              type: 'button',
              style: `--i:${i}`,
            },
            NEXT_LABEL[a],
          )
          b.addEventListener('click', () => cb.onChoose(a))
          return b
        })
        own.style.setProperty('--i', String(rows.length))
        fill(fallbacks, ...rows, s.next.length > 0 ? own : null)
      }
      if (s.failure === null) manual.hidden = true
    },
    showManual() {
      manual.hidden = false
      query.focus()
    },
    flash(ms) {
      const f = h('div', { class: 'flash', 'aria-hidden': 'true' })
      document.body.append(f)
      return new Promise((resolve) =>
        setTimeout(() => {
          f.remove()
          resolve()
        }, ms),
      )
    },
  }
}
