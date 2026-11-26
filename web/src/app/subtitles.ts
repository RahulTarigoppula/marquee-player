// The subtitle on the picture: one at a time, either a WebVTT <track> (SRT and VTT, converted
// once, re-emitted as a Blob URL when the sync moves) or an ASS renderer (JASSUB, loaded only
// when an .ass/.ssa file attaches). Owns the sync offset, the size and the on/off choice.
import { languageLabel } from '../engine/languages'
import { decodeSubtitle, parseSidecar, sidecarKind } from '../engine/sidecar'
import { type Cue, toVtt } from '../engine/srt2vtt'
import { snap } from '../engine/syncRule'
import type { MovieHash } from '../engine/types'
import * as idb from '../storage/idb'
import type { AssTrack } from '../ui/ass'
import type { AuditoriumView } from '../ui/auditorium'
import { type BoothTrack, type BoothView, CUE_SCALE, type CueSize } from '../ui/booth'
import { h } from '../ui/dom'

const RESYNC_DEBOUNCE_MS = 120

export interface Subtitle {
  label: string
  status: BoothTrack['status']
  /** The OpenSubtitles file_id, so "Find another print" never offers it again. */
  fileId: string | null
}

export interface SubtitleDeps {
  aud: AuditoriumView
  sheet: BoothView
  /** The subtitle language (the <track>'s srclang). */
  language(): string
  /** The film's moviehash, once known: the key for a remembered file and offset. */
  hash(): MovieHash | null
  /** No subtitle yet and the viewer asked for one: open the file picker. */
  pickFile(): void
  /** The viewer moved the sync: remember it for this film. */
  onDelay(hash: MovieHash, delay: number): void
  cueSize: CueSize
  onCueSize(size: CueSize): void
}

export interface SubtitleView {
  readonly current: Subtitle | null
  readonly delay: number
  /** Replace whatever is on screen with these cues (an ASS renderer is torn down first). */
  setCues(cues: Cue[], sub: Subtitle): void
  /** A subtitle file from this device: SRT, VTT or ASS/SSA. */
  attach(file: File): Promise<void>
  show(on: boolean): void
  toggle(): void
  /** `remember` false: a recalled offset, not a change the viewer made. */
  setDelay(v: number, remember?: boolean): void
  setCueSize(size: CueSize): void
  /** The moviehash is now known: cache a file the viewer added before it was. */
  hashKnown(): void
  /** Render the track list (booth) and the subtitles button. */
  render(): void
  clear(): void
}

export function subtitles(d: SubtitleDeps): SubtitleView {
  const { aud, sheet } = d
  const video = aud.video
  let cues: Cue[] | null = null
  let ass: AssTrack | null = null
  let current: Subtitle | null = null
  let on = true
  let delay = 0
  let cueSize = d.cueSize
  let trackUrl: string | null = null
  /** A sidecar SRT/VTT waiting for the moviehash so it can be remembered for next time. */
  let toCache: { cues: Cue[]; name: string } | null = null
  let resync: ReturnType<typeof setTimeout> | undefined

  const dropTrack = () => {
    for (const t of video.querySelectorAll('track')) t.remove()
    if (trackUrl) URL.revokeObjectURL(trackUrl)
    trackUrl = null
  }

  const applyTrack = () => {
    dropTrack()
    if (!cues) return
    trackUrl = URL.createObjectURL(
      new Blob([toVtt(cues, Math.round(delay * 1000))], { type: 'text/vtt' }),
    )
    const lang = d.language()
    const track = h('track', {
      kind: 'subtitles',
      srclang: lang,
      label: current?.label ?? languageLabel(lang),
      src: trackUrl,
      default: on,
    })
    video.append(track)
    // The viewer's Off survives a sync change: the re-emitted track keeps their choice.
    track.track.mode = on ? 'showing' : 'hidden'
  }

  const render = () => {
    const list: BoothTrack[] = current
      ? [{ id: 'current', label: current.label, status: current.status }]
      : []
    sheet.setTracks(list, current && on ? 'current' : null)
    aud.setSubs(current !== null, on)
  }

  const cacheSidecar = () => {
    const hash = d.hash()
    if (!toCache || !hash) return
    const vttText = toVtt(toCache.cues)
    const release = toCache.name
    toCache = null
    void idb.subtitles
      .put({
        hash,
        language: idb.SIDECAR_LANG,
        provider: 'sidecar',
        release,
        syncedByHash: false,
        vttText,
        bytes: vttText.length,
        fetchedAt: Date.now(),
      })
      .catch(() => undefined)
  }

  const setCues = (next: Cue[], sub: Subtitle) => {
    ass?.destroy()
    ass = null
    cues = next
    current = sub
    on = true
    applyTrack()
    render()
  }

  const show = (next: boolean) => {
    if (!current) {
      if (next) d.pickFile()
      return
    }
    on = next
    for (const t of video.textTracks) t.mode = next ? 'showing' : 'hidden'
    ass?.setVisible(next)
    render()
  }

  return {
    get current() {
      return current
    },
    get delay() {
      return delay
    },
    setCues,
    async attach(file) {
      const kind = sidecarKind(file.name)
      if (!kind) return
      const text = decodeSubtitle(new Uint8Array(await file.arrayBuffer()))
      if (kind === 'ass') {
        const { attachAss } = await import('../ui/ass')
        const renderer = await attachAss(video, text)
        // Only one subtitle at a time: the text track (if any) goes.
        ass?.destroy()
        cues = null
        toCache = null
        dropTrack()
        ass = renderer
        current = { label: file.name, status: 'yours', fileId: null }
        on = true
        renderer.setDelay(delay)
        renderer.setScale(CUE_SCALE[cueSize])
        render()
        return
      }
      const parsed = parseSidecar(kind, text) ?? []
      if (parsed.length === 0) {
        aud.notice(`${file.name} has no subtitles this player can read.`)
        return
      }
      setCues(parsed, { label: file.name, status: 'yours', fileId: null })
      toCache = { cues: parsed, name: file.name }
      cacheSidecar()
    },
    show,
    toggle: () => show(!on),
    setDelay(v, remember = true) {
      delay = snap(v)
      sheet.setSync(delay)
      aud.setSubDelay(delay)
      ass?.setDelay(delay)
      clearTimeout(resync)
      if (cues) resync = setTimeout(applyTrack, RESYNC_DEBOUNCE_MS) // re-emit the shifted VTT
      const hash = d.hash()
      if (remember && hash) d.onDelay(hash, delay)
    },
    setCueSize(size) {
      cueSize = size
      aud.setCueScale(CUE_SCALE[size])
      ass?.setScale(CUE_SCALE[size])
      d.onCueSize(size)
    },
    hashKnown: cacheSidecar,
    render,
    clear() {
      clearTimeout(resync)
      dropTrack()
      cues = null
      ass?.destroy()
      ass = null
      current = null
      toCache = null
      on = true
      render()
    },
  }
}
