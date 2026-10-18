// The perforated ticket strip (§3.6.5). The count decrements AFTER the tear animation, so the
// strip is rebuilt only when what it shows changes — never per animation frame, which would
// replace the stub mid-tear.
import type { TicketStrip } from '../engine/types'
import { fill, h } from './dom'

const MAX_STUBS = 10

// Lite cannot spend the anonymous per-IP pool (the Worker's IP would pay for it), so signed out
// it says what is true here instead of the native strip's "ANONYMOUS · 5 PER DAY PER IP".
const SIGNED_OUT_TEXT = 'NOT SIGNED IN'
const SIGNED_OUT_ARIA = 'Not signed in: downloading subtitles needs a free OpenSubtitles account'
const SIGNED_OUT_SENTENCE = 'Sign in free to download subtitles'

export interface TicketStripView {
  el: HTMLElement
  render(strip: TicketStrip, stubs: number): void
  /** Tear the last stub; resolves when the 240 ms animation has finished. */
  tear(): Promise<void>
}

export function ticketStrip(onSentence?: () => void): TicketStripView {
  const tickets = h('div', { class: 'tickets', 'aria-hidden': 'true' })
  const label = h('span', { class: 'ticketlabel', 'aria-hidden': 'true' })
  const sr = h('span', { class: 'sr' })
  const sentence = h('button', { class: 'linkbtn ticketsentence', type: 'button', hidden: true })
  if (onSentence) sentence.addEventListener('click', onSentence)
  const el = h(
    'div',
    { class: 'ticketstrip', role: 'group', 'aria-label': 'Tickets' },
    tickets,
    label,
    sr,
    sentence,
  )
  let shown = ''

  return {
    el,
    render(strip, stubs) {
      const anon = strip.state === 'anonymous'
      const text = anon ? SIGNED_OUT_TEXT : strip.text
      const line = anon ? (onSentence ? SIGNED_OUT_SENTENCE : null) : strip.sentence
      const n = Math.max(0, Math.min(MAX_STUBS, stubs))
      const key = `${strip.state}|${text}|${line}|${n}`
      if (key === shown) return
      shown = key
      el.dataset.state = strip.state
      el.classList.toggle('is-low', strip.state === 'two-left' || strip.state === 'exhausted')
      label.textContent = text
      sr.textContent = anon ? SIGNED_OUT_ARIA : strip.ariaLabel
      sentence.hidden = line === null || !onSentence
      sentence.textContent = line ?? ''
      fill(tickets, ...Array.from({ length: n }, () => h('i', { class: 'ticket' })))
    },
    tear() {
      const last = tickets.lastElementChild
      if (!last) return Promise.resolve()
      last.classList.add('torn')
      return new Promise((resolve) => {
        const done = () => resolve()
        last.addEventListener('animationend', done, { once: true })
        setTimeout(done, 320) // reduced motion, a hidden strip, or no animation support
      })
    },
  }
}
