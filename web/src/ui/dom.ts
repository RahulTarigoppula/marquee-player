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

export const ICONS = {
  play: ['M6 3l14 9-14 9V3z'],
  pause: ['M6 4h4v16H6z', 'M14 4h4v16h-4z'],
  captions: ['M3 5h18v14H3z', 'M7 15h4', 'M15 15h2', 'M7 11h2', 'M13 11h4'],
  maximize: ['M15 3h6v6', 'M9 21H3v-6', 'M21 3l-7 7', 'M3 21l7-7'],
  pip: ['M2 10V6a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-6', 'M2 14h8v6H2z'],
  back: ['M19 12H5', 'M12 19l-7-7 7-7'],
} as const

/** Replace an element's children in one go. */
export function fill(el: Element, ...children: Child[]): void {
  el.replaceChildren(
    ...children.filter((c): c is Node | string => c !== null && c !== undefined && c !== false),
  )
}
