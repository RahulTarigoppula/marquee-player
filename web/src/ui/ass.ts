// ASS/SSA through JASSUB (libass in WASM). This module is ONLY reached by dynamic import()
// when an .ass/.ssa attaches, so ~1.2 MB of WASM never touches the landing page. GitHub Pages
// cannot send COOP/COEP, so there is no SharedArrayBuffer: JASSUB runs single-threaded.
import JASSUB from 'jassub'

export interface AssTrack {
  setDelay(seconds: number): void
  destroy(): void
}

export async function attachAss(video: HTMLVideoElement, content: string): Promise<AssTrack> {
  const renderer = new JASSUB({ video, subContent: content })
  await renderer.ready
  return {
    // Positive delay = subtitles later, so the renderer samples an earlier time.
    setDelay(seconds) {
      renderer.timeOffset = -seconds
    },
    destroy() {
      void renderer.destroy()
    },
  }
}
