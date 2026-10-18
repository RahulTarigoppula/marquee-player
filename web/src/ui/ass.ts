// ASS/SSA through JASSUB (libass in WASM). This module is ONLY reached by dynamic import()
// when an .ass/.ssa attaches, so ~1.2 MB of WASM never touches the landing page. GitHub Pages
// cannot send COOP/COEP, so there is no SharedArrayBuffer: JASSUB runs single-threaded.
import JASSUB from 'jassub'

export interface AssTrack {
  setDelay(seconds: number): void
  /** Subtitles Off hides the libass canvas; On shows it again. */
  setVisible(on: boolean): void
  /** The booth's S/M/L: every style's FontSize, relative to the file's own. */
  setScale(scale: number): void
  destroy(): void
}

interface StyleLike {
  FontSize: number
  [k: string]: unknown
}
interface RendererLike {
  getStyles(): Promise<StyleLike[]>
  setStyle(style: StyleLike, index: number): Promise<void>
}

export async function attachAss(video: HTMLVideoElement, content: string): Promise<AssTrack> {
  const renderer = new JASSUB({ video, subContent: content })
  await renderer.ready
  const remote = renderer.renderer as unknown as RendererLike
  let original: StyleLike[] | null = null
  let destroyed = false
  return {
    // Positive delay = subtitles later, so the renderer samples an earlier time.
    setDelay(seconds) {
      renderer.timeOffset = -seconds
    },
    setVisible(on) {
      renderer._canvas.style.visibility = on ? 'visible' : 'hidden'
    },
    setScale(scale) {
      void (async () => {
        try {
          original ??= await remote.getStyles()
          if (destroyed) return
          await Promise.all(
            original.map((s, i) => remote.setStyle({ ...s, FontSize: s.FontSize * scale }, i)),
          )
          await renderer.resize(true)
        } catch {
          // an old renderer without style access: the size stays as authored
        }
      })()
    },
    destroy() {
      destroyed = true
      void renderer.destroy()
    },
  }
}
