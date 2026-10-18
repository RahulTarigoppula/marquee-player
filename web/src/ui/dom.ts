// A tiny element builder. Text always goes in as text nodes — never innerHTML — so no
// subtitle, filename or release name can ever become markup.

type Attr = string | number | boolean | null | undefined
type Child = Node | string | null | undefined | false

export function h<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs: Record<string, Attr> = {},
  ...children: Child[]
): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag)
  for (const [k, v] of Object.entries(attrs)) {
    if (v === null || v === undefined || v === false) continue
    el.setAttribute(k, v === true ? '' : String(v))
  }
  for (const c of children) {
    if (c === null || c === undefined || c === false) continue
    el.append(typeof c === 'string' ? document.createTextNode(c) : c)
  }
  return el
}

const SVG_NS = 'http://www.w3.org/2000/svg'

/** A Lucide-style icon (ISC) from path data: 24-unit viewBox, stroked, aria-hidden. */
export function icon(...paths: string[]): SVGSVGElement {
  const svg = document.createElementNS(SVG_NS, 'svg')
  svg.setAttribute('viewBox', '0 0 24 24')
  svg.setAttribute('aria-hidden', 'true')
  svg.setAttribute('focusable', 'false')
  for (const d of paths) {
    const p = document.createElementNS(SVG_NS, 'path')
    p.setAttribute('d', d)
    svg.append(p)
  }
  return svg
}

const SPEAKER = 'M11 5 6 9H2v6h4l5 4V5z'

export const ICONS = {
  play: ['M6 3l14 9-14 9V3z'],
  pause: ['M6 4h4v16H6z', 'M14 4h4v16h-4z'],
  captions: [
    'M3 7a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
    'M7 15h4',
    'M15 15h2',
    'M7 11h2',
    'M13 11h4',
  ],
  maximize: ['M15 3h6v6', 'M9 21H3v-6', 'M21 3l-7 7', 'M3 21l7-7'],
  minimize: ['M4 14h6v6', 'M20 10h-6V4', 'M14 10l7-7', 'M3 21l7-7'],
  pip: ['M2 10V6a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-6', 'M2 14h8v6H2z'],
  back: ['M19 12H5', 'M12 19l-7-7 7-7'],
  volume: [SPEAKER, 'M15.54 8.46a5 5 0 0 1 0 7.07', 'M19.07 4.93a10 10 0 0 1 0 14.14'],
  volumeLow: [SPEAKER, 'M15.54 8.46a5 5 0 0 1 0 7.07'],
  volumeOff: [SPEAKER, 'M22 9l-6 6', 'M16 9l6 6'],
  rewind: ['M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8', 'M3 3v5h5'],
  forward: ['M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8', 'M21 3v5h-5'],
  filePlus: [
    'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z',
    'M14 2v6h6',
    'M12 18v-6',
    'M9 15h6',
  ],
  close: ['M18 6 6 18', 'M6 6l12 12'],
  gauge: ['M12 14l4-4', 'M3.34 19a10 10 0 1 1 17.32 0'],
  film: [
    'M3 5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
    'M7 3v18',
    'M17 3v18',
    'M3 7.5h4',
    'M3 12h18',
    'M3 16.5h4',
    'M17 7.5h4',
    'M17 16.5h4',
  ],
  keyboard: [
    'M4 5h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z',
    'M6 9h.01',
    'M10 9h.01',
    'M14 9h.01',
    'M18 9h.01',
    'M8 13h.01',
    'M16 13h.01',
    'M7 16h10',
  ],
} as const

const FOCUSABLE =
  'a[href],button:not([disabled]),input:not([disabled]):not([tabindex="-1"]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])'

/** The keyboard-focusable elements inside `root`, in DOM order, skipping hidden subtrees. */
export function focusables(root: HTMLElement): HTMLElement[] {
  return [...root.querySelectorAll<HTMLElement>(FOCUSABLE)].filter(
    (el) => el.closest('[hidden],[inert]') === null || el.closest('[hidden],[inert]') === root,
  )
}

/**
 * Keep Tab inside `root` (a modal dialog) and, on release, give focus back to whatever had it
 * when the dialog opened.
 */
export function trapFocus(root: HTMLElement): () => void {
  const before = document.activeElement instanceof HTMLElement ? document.activeElement : null
  const onKey = (e: KeyboardEvent) => {
    if (e.key !== 'Tab') return
    const f = focusables(root)
    const first = f[0]
    const last = f.at(-1)
    if (!first || !last) {
      e.preventDefault()
      return
    }
    const active = document.activeElement
    const inside = active instanceof Node && root.contains(active)
    if (e.shiftKey && (active === first || !inside)) {
      e.preventDefault()
      last.focus()
    } else if (!e.shiftKey && (active === last || !inside)) {
      e.preventDefault()
      first.focus()
    }
  }
  document.addEventListener('keydown', onKey, true)
  return () => {
    document.removeEventListener('keydown', onKey, true)
    // After the caller has re-lit the layer underneath (inert/hidden update synchronously).
    queueMicrotask(() => {
      if (before?.isConnected && !before.closest('[inert],[hidden]')) before.focus()
    })
  }
}

/** Replace an element's children in one go. */
export function fill(el: Element, ...children: Child[]): void {
  el.replaceChildren(
    ...children.filter((c): c is Node | string => c !== null && c !== undefined && c !== false),
  )
}
