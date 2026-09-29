// The Subtitle Booth (§4.4): a sheet that never exceeds 70 % of the height, over a paused
// frame. Tracks, size S/M/L, the sync rule (FIXED caret, MOVING ruler), "Find another print"
// and the ticket count.
import { ariaValueText, RANGE, readout, snap, step } from '../engine/syncRule'
import type { ScoredCandidate } from '../engine/types'
import { fill, h } from './dom'
import { candidateRow } from './leader'

export const PX_PER_SECOND = 200 // 10 px per 50 ms detent
const TICK_S = 0.05
const MAJOR_EVERY = 10 // a labelled major every 0.50 s

export type CueSize = 'S' | 'M' | 'L'
export const CUE_SCALE: Readonly<Record<CueSize, number>> = { S: 0.86, M: 1, L: 1.22 }

export interface BoothTrack {
  id: string
  label: string
  status: 'synced' | 'by-name' | null
}

export interface BoothOptions {
  onTrack(id: string | null): void
  onSize(size: CueSize): void
  onSync(v: number): void
  onFindAnother(): void
  onPick(c: ScoredCandidate): void
  onClose(): void
}

export interface BoothView {
  el: HTMLElement
  readonly isOpen: boolean
  open(): void
  close(): void
  setTracks(tracks: BoothTrack[], selected: string | null): void
  setSync(v: number): void
  setTickets(text: string): void
  setCandidates(
    list: ScoredCandidate[],
    picked: ScoredCandidate | null,
    sentence: string | null,
  ): void
}

/** The ruler's ticks, −2.00 … +2.00, drawn once. */
function ticks(): HTMLElement {
  const box = h('div', { class: 'rule__ticks', 'aria-hidden': 'true' })
  const n = Math.round(RANGE / TICK_S)
  for (let i = -n; i <= n; i++) {
    const x = i * TICK_S * PX_PER_SECOND
    const major = i % MAJOR_EVERY === 0
    box.append(h('i', { class: major ? 'major' : null, style: `left:${x}px` }))
    if (major) {
      const v = i * TICK_S
      const text = `${v < 0 ? '−' : v > 0 ? '+' : ''}${Math.abs(v).toFixed(2)}`
      box.append(h('b', { style: `left:${x}px` }, text))
    }
  }
  return box
}

export function booth(o: BoothOptions): BoothView {
  let value = 0
  const ruler = ticks()
  const rule = h(
    'div',
    {
      class: 'rule',
      role: 'slider',
      tabindex: 0,
      'aria-label': 'Subtitle sync',
      'aria-valuemin': -RANGE,
      'aria-valuemax': RANGE,
      'aria-valuenow': 0,
      'aria-valuetext': ariaValueText(0),
    },
    ruler,
    h('div', { class: 'rule__caret', 'aria-hidden': 'true' }),
  )
  const syncOut = h('span', { class: 'mono' }, readout(0))
  const tracks = h('div', { role: 'radiogroup', 'aria-label': 'Subtitle tracks' })
  const sizes = (['S', 'M', 'L'] as const).map((s) => {
    const b = h(
      'button',
      { class: 'preset', type: 'button', 'aria-pressed': s === 'M' ? 'true' : 'false' },
      s,
    )
    b.addEventListener('click', () => {
      for (const x of sizes) x.setAttribute('aria-pressed', x === b ? 'true' : 'false')
      o.onSize(s)
    })
    return b
  })
  const tickets = h('span', { class: 'ticketlabel' })
  const find = h('button', { class: 'btn', type: 'button' }, 'Find another print')
  find.addEventListener('click', o.onFindAnother)
  const results = h('div', { class: 'rows', role: 'radiogroup', 'aria-label': 'Other prints' })
  const sentence = h('p', { class: 'sentence', role: 'status' })
  const close = h('button', { class: 'mark', type: 'button', 'aria-label': 'Close the booth' }, '×')
  close.addEventListener('click', o.onClose)

  const el = h(
    'section',
    {
      class: 'sheet',
      role: 'dialog',
      'aria-modal': 'false',
      'aria-label': 'Subtitle booth',
      hidden: true,
    },
    h('div', { class: 'grain', 'aria-hidden': 'true' }),
    h(
      'div',
      { class: 'sheet__body' },
      h('div', { class: 'sheet__head' }, h('span', { class: 'label' }, 'Tracks'), close),
      tracks,
      h(
        'div',
        { class: 'sheet__sec' },
        h('span', { class: 'label' }, 'Style · size'),
        h('div', { class: 'presets', role: 'group', 'aria-label': 'Subtitle size' }, ...sizes),
      ),
      h(
        'div',
        { class: 'sheet__sec' },
        h('div', { class: 'sheet__head' }, h('span', { class: 'label' }, 'Sync'), syncOut),
        rule,
      ),
      h(
        'div',
        { class: 'sheet__sec' },
        h('div', { class: 'sheet__head' }, find, tickets),
        sentence,
        results,
      ),
    ),
  )

  const set = (v: number) => {
    value = snap(v)
    ruler.style.setProperty('--rx', `${-value * PX_PER_SECOND}px`) // the RULER moves
    rule.setAttribute('aria-valuenow', value.toFixed(2))
    rule.setAttribute('aria-valuetext', ariaValueText(value))
    syncOut.textContent = readout(value)
  }

  let drag: { x: number; v: number } | null = null
  rule.addEventListener('pointerdown', (e) => {
    rule.setPointerCapture(e.pointerId)
    drag = { x: e.clientX, v: value }
  })
  rule.addEventListener('pointermove', (e) => {
    if (!drag) return
    const v = snap(drag.v - (e.clientX - drag.x) / PX_PER_SECOND)
    if (v !== value) o.onSync(v)
  })
  const end = () => {
    drag = null
  }
  rule.addEventListener('pointerup', end)
  rule.addEventListener('pointercancel', end)
  rule.addEventListener('keydown', (e) => {
    const k = e.key.toLowerCase()
    const later = e.key === 'ArrowRight' || e.key === 'ArrowUp' || k === 'k'
    const earlier = e.key === 'ArrowLeft' || e.key === 'ArrowDown' || k === 'j'
    if (e.key === 'Home') o.onSync(0)
    else if (later || earlier) o.onSync(step(value, { isK: later, shift: e.shiftKey }))
    else return
    e.preventDefault()
    e.stopPropagation()
  })

  el.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      e.stopPropagation()
      o.onClose()
    }
  })

  return {
    el,
    get isOpen() {
      return !el.hidden
    },
    open() {
      el.hidden = false
      rule.focus()
    },
    close() {
      el.hidden = true
    },
    setTracks(list, selected) {
      const rows = [...list, { id: '', label: 'Off', status: null } as BoothTrack].map((t) => {
        const on = (t.id === '' ? null : t.id) === selected
        const b = h(
          'button',
          {
            class: 'trackrow',
            type: 'button',
            role: 'radio',
            'aria-checked': on ? 'true' : 'false',
          },
          h('i', { class: 'trackrow__dot', 'aria-hidden': 'true' }),
          h('span', { class: 'trackrow__t' }, t.label),
          t.status === 'synced' ? h('span', { class: 'oklabel' }, 'synced ✓') : null,
          t.status === 'by-name' ? h('span', { class: 'warnlabel' }, 'CHECK SYNC') : null,
        )
        b.addEventListener('click', () => o.onTrack(t.id === '' ? null : t.id))
        return b
      })
      fill(tracks, ...rows)
    },
    setSync: set,
    setTickets(text) {
      tickets.textContent = text
    },
    setCandidates(list, picked, text) {
      sentence.textContent = text ?? ''
      fill(results, ...list.map((c) => candidateRow(c, c === picked, () => o.onPick(c))))
    },
  }
}
