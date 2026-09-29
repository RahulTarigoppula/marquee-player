// The perforated ticket strip (§3.6.5). The count decrements AFTER the tear animation.
import type { TicketStrip } from '../engine/types'
import { fill, h } from './dom'

const MAX_STUBS = 10

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

  return {
    el,
    render(strip, stubs) {
      el.dataset.state = strip.state
      el.classList.toggle('is-low', strip.state === 'two-left' || strip.state === 'exhausted')
      label.textContent = strip.text
      sr.textContent = strip.ariaLabel
      sentence.hidden = strip.sentence === null
      sentence.textContent = strip.sentence ?? ''
      const n = Math.max(0, Math.min(MAX_STUBS, stubs))
      fill(tickets, ...Array.from({ length: n }, () => h('i', { class: 'ticket' })))
    },
    tear() {
      const last = tickets.lastElementChild
      if (!last) return Promise.resolve()
      last.classList.add('torn')
      return new Promise((resolve) => {
        const done = () => resolve()
        last.addEventListener('animationend', done, { once: true })
        setTimeout(done, 320) // reduced motion or no animation support
      })
    },
  }
}
