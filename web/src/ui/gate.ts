// The film gate (§3.6.3): a 56 px strip of 35 mm film as the seek bar. role="slider" with a
// timecode aria-valuetext; 5-minute detents (the web has no chapter list); release snaps to a
// detent within 6 px; dragging UP off the strip switches to FINE (1/8 gain, no detents).
import { fmt } from '../engine/timecode'
import { fill, h } from './dom'

export const DETENT_EVERY_S = 300
export const CAPTURE_PX = 6
export const FINE_GAIN = 1 / 8
const FINE_LIFT_PX = 24
const KEY_STEP_S = 5
const KEY_SHIFT_STEP_S = 30

export function detentsFor(duration: number): number[] {
  const out: number[] = []
  for (let t = 0; t <= duration; t += DETENT_EVERY_S) out.push(t)
  return out
}

/** Release position → seek target, snapping to the nearest detent within the capture radius. */
export function snapTarget(
  releasePx: number,
  widthPx: number,
  duration: number,
  detents: number[],
): number {
  const secondsPerPx = duration / widthPx
  let best: number | null = null
  let bestDist = Number.POSITIVE_INFINITY
  for (const d of detents) {
    const dist = Math.abs(d / secondsPerPx - releasePx)
    if (dist < bestDist) {
      best = d
      bestDist = dist
    }
  }
  return best !== null && bestDist <= CAPTURE_PX ? best : releasePx * secondsPerPx
}

export interface GateView {
  el: HTMLElement
  update(position: number, duration: number, bufferedEnd: number, buffering: boolean): void
}

export function filmGate(onSeek: (t: number) => void): GateView {
  const buf = h('div', { class: 'gate__buf' })
  const played = h('div', { class: 'gate__played' })
  const marks = h('div', { 'aria-hidden': 'true' })
  const tc = h('span', { class: 'gate__tc' })
  const frame = h('div', { class: 'gate__frame' }, tc)
  const fine = h('span', { class: 'gate__fine', hidden: true }, 'FINE')
  const el = h(
    'div',
    {
      class: 'gate',
      role: 'slider',
      tabindex: 0,
      'aria-label': 'Film gate — seek',
      'aria-valuemin': 0,
      'aria-valuemax': 0,
      'aria-valuenow': 0,
      'aria-valuetext': '00:00:00',
    },
    h('div', { class: 'gate__perf gate__perf--t', 'aria-hidden': 'true' }),
    h('div', { class: 'gate__strip', 'aria-hidden': 'true' }),
    buf,
    played,
    marks,
    h('div', { class: 'gate__perf gate__perf--b', 'aria-hidden': 'true' }),
    frame,
    fine,
  )

  let pos = 0
  let dur = 0
  let marksFor = -1
  let drag: { startX: number; startY: number; anchor: number; fine: boolean; t: number } | null =
    null

  const draw = (t: number) => {
    const pct = dur > 0 ? (t / dur) * 100 : 0
    played.style.width = `${pct}%`
    frame.style.left = `${pct}%`
    tc.textContent = fmt(t)
    el.setAttribute('aria-valuenow', String(Math.floor(t)))
    el.setAttribute('aria-valuetext', `${fmt(t)} of ${fmt(dur)}`)
  }
  const at = (clientX: number) => {
    const r = el.getBoundingClientRect()
    return Math.max(0, Math.min(r.width, clientX - r.left))
  }
  const detentFlash = () => {
    el.classList.add('is-detent')
    requestAnimationFrame(() => el.classList.remove('is-detent'))
  }

  el.addEventListener('pointerdown', (e) => {
    if (dur <= 0) return
    el.setPointerCapture(e.pointerId)
    const width = el.getBoundingClientRect().width || 1
    const t = (at(e.clientX) / width) * dur
    drag = { startX: e.clientX, startY: e.clientY, anchor: t, fine: false, t }
    el.classList.add('is-drag')
    draw(t)
  })
  el.addEventListener('pointermove', (e) => {
    if (!drag) return
    const width = el.getBoundingClientRect().width || 1
    const spp = dur / width
    drag.fine = drag.startY - e.clientY > FINE_LIFT_PX
    fine.hidden = !drag.fine
    const prev = drag.t
    const next = drag.fine
      ? Math.max(0, Math.min(dur, drag.anchor + (e.clientX - drag.startX) * FINE_GAIN * spp))
      : (at(e.clientX) / width) * dur
    drag.t = next
    if (!drag.fine && detentsFor(dur).some((d) => (prev - d) * (next - d) < 0)) detentFlash()
    draw(next)
  })
  const release = (e: PointerEvent) => {
    if (!drag) return
    const width = el.getBoundingClientRect().width || 1
    const t = drag.fine ? drag.t : snapTarget(at(e.clientX), width, dur, detentsFor(dur))
    drag = null
    el.classList.remove('is-drag')
    fine.hidden = true
    draw(t)
    onSeek(t)
  }
  el.addEventListener('pointerup', release)
  el.addEventListener('pointercancel', release)

  el.addEventListener('keydown', (e) => {
    const detents = detentsFor(dur)
    let t: number | null = null
    const step = e.shiftKey ? KEY_SHIFT_STEP_S : KEY_STEP_S
    if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') t = pos - step
    else if (e.key === 'ArrowRight' || e.key === 'ArrowUp') t = pos + step
    else if (e.key === 'Home') t = 0
    else if (e.key === 'End') t = dur
    else if (e.key === 'PageUp') t = detents.find((d) => d > pos + 0.5) ?? dur
    else if (e.key === 'PageDown') t = [...detents].reverse().find((d) => d < pos - 0.5) ?? 0
    if (t === null) return
    e.preventDefault()
    e.stopPropagation()
    onSeek(Math.max(0, Math.min(dur, t)))
  })

  return {
    el,
    update(position, duration, bufferedEnd, buffering) {
      pos = position
      dur = Number.isFinite(duration) ? duration : 0
      el.setAttribute('aria-valuemax', String(Math.floor(dur)))
      el.classList.toggle('is-buffering', buffering)
      buf.style.width = dur > 0 ? `${(bufferedEnd / dur) * 100}%` : '0'
      if (marksFor !== dur) {
        marksFor = dur
        fill(
          marks,
          ...detentsFor(dur)
            .slice(1)
            .map((d) => h('i', { class: 'gate__detent', style: `left:${(d / dur) * 100}%` })),
        )
      }
      if (!drag) draw(position)
    },
  }
}
