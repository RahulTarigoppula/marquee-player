// The seek bar (the film gate, §3.6.3, made slim): played in tungsten, buffered in warm grey, a
// hover/drag time tip, 5-minute detents (the web has no chapter list) that a release snaps to
// within 6 px, and dragging UP off the bar switches to FINE (1/8 gain, no detents).
// role="slider" with a timecode aria-valuetext.
import { fmt } from '../engine/timecode'
import { fill, h, setAttr } from './dom'

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

/** A player clock: 4:05, 1:02:13 (hours only when the film has them). */
export function clock(seconds: number, withHours = seconds >= 3600): string {
  const s = Math.max(0, Math.floor(Number.isFinite(seconds) ? seconds : 0))
  const hh = Math.floor(s / 3600)
  const mm = Math.floor((s % 3600) / 60)
  const ss = String(s % 60).padStart(2, '0')
  return withHours ? `${hh}:${String(mm).padStart(2, '0')}:${ss}` : `${mm}:${ss}`
}

export interface GateView {
  el: HTMLElement
  update(position: number, duration: number, bufferedEnd: number, buffering: boolean): void
}

export function filmGate(onSeek: (t: number) => void): GateView {
  const buf = h('div', { class: 'seek__buf' })
  const played = h('div', { class: 'seek__played' })
  const hover = h('div', { class: 'seek__hover' })
  const marks = h('div', { class: 'seek__marks' })
  const thumb = h('div', { class: 'seek__thumb' })
  const tip = h('div', { class: 'seek__tip', hidden: true })
  const fine = h('span', { class: 'seek__fine', hidden: true }, 'FINE')
  const el = h(
    'div',
    {
      class: 'seek',
      role: 'slider',
      tabindex: 0,
      'aria-label': 'Seek',
      'aria-valuemin': 0,
      'aria-valuemax': 0,
      'aria-valuenow': 0,
      'aria-valuetext': '00:00:00',
    },
    h('div', { class: 'seek__track', 'aria-hidden': 'true' }, buf, hover, played, marks),
    h('div', { 'aria-hidden': 'true' }, thumb, tip, fine),
  )

  let pos = 0
  let dur = 0
  let marksFor = -1
  let drag: { startX: number; startY: number; anchor: number; fine: boolean; t: number } | null =
    null

  const pct = (t: number) => (dur > 0 ? Math.max(0, Math.min(100, (t / dur) * 100)) : 0)
  // Widths are rounded to 0.01 % (a sub-pixel on any screen) so a steady frame writes nothing.
  const pctText = (t: number) => `${pct(t).toFixed(2)}%`
  let drawn = ''
  let buffered = ''
  const draw = (t: number) => {
    const p = pctText(t)
    if (p !== drawn) {
      drawn = p
      played.style.width = p
      thumb.style.left = p
    }
    setAttr(el, 'aria-valuenow', String(Math.floor(t)))
    setAttr(el, 'aria-valuetext', `${fmt(t)} of ${fmt(dur)}`)
  }
  // The bar's box is read once per gesture (or per hover move), never after a style write in
  // the same frame.
  let box: DOMRect | null = null
  const rect = () => {
    box ??= el.getBoundingClientRect()
    return box
  }
  const at = (clientX: number) => {
    const r = rect()
    return Math.max(0, Math.min(r.width, clientX - r.left))
  }
  const showTip = (t: number) => {
    if (dur <= 0) return
    tip.hidden = false
    tip.textContent = clock(t, dur >= 3600)
    tip.style.left = `${pct(t)}%`
  }
  const detentFlash = () => {
    el.classList.add('is-detent')
    requestAnimationFrame(() => el.classList.remove('is-detent'))
  }

  const forgetBox = () => {
    box = null
  }
  el.addEventListener('pointerenter', forgetBox)
  window.addEventListener('resize', forgetBox, { passive: true })
  el.addEventListener('pointerdown', (e) => {
    if (dur <= 0 || e.button > 0) return
    box = null
    el.setPointerCapture?.(e.pointerId)
    const width = rect().width || 1
    const t = (at(e.clientX) / width) * dur
    drag = { startX: e.clientX, startY: e.clientY, anchor: t, fine: false, t }
    el.classList.add('is-drag')
    draw(t)
    showTip(t)
  })
  el.addEventListener(
    'pointermove',
    (e) => {
      const width = rect().width || 1
      if (!drag) {
        if (e.pointerType === 'mouse') {
          const t = (at(e.clientX) / width) * dur
          hover.style.width = `${pct(t)}%`
          showTip(t)
        }
        return
      }
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
      showTip(next)
    },
    { passive: true },
  )
  el.addEventListener('pointerleave', () => {
    forgetBox()
    if (drag) return
    tip.hidden = true
    hover.style.width = '0'
  })
  const release = (e: PointerEvent) => {
    if (!drag) return
    const width = rect().width || 1
    const t = drag.fine ? drag.t : snapTarget(at(e.clientX), width, dur, detentsFor(dur))
    drag = null
    el.classList.remove('is-drag')
    fine.hidden = true
    if (e.pointerType !== 'mouse') tip.hidden = true
    draw(t)
    onSeek(t)
    // A seek by pointer hands the focus back: the arrows and Space then mean what they mean in
    // the rest of the player, not "nudge the bar".
    el.blur()
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
      setAttr(el, 'aria-valuemax', String(Math.floor(dur)))
      el.classList.toggle('is-buffering', buffering)
      const b = pctText(bufferedEnd)
      if (b !== buffered) {
        buffered = b
        buf.style.width = b
      }
      if (marksFor !== dur) {
        marksFor = dur
        fill(
          marks,
          ...detentsFor(dur)
            .slice(1)
            .filter((d) => d < dur)
            .map((d) => h('i', { class: 'seek__detent', style: `left:${(d / dur) * 100}%` })),
        )
      }
      if (!drag) draw(position)
    },
  }
}
