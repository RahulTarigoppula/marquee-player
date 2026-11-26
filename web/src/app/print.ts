// What the browser makes of a print: does it play at all, and does it have a picture and sound?
import { noPrintReason, type PrintSniff, sniffPrint } from '../engine/capability'
import { HashUnavailable, isFileTooSmall, osHash } from '../engine/osHash'
import type { Capability, MovieHash } from '../engine/types'
import type { NoticeLink } from '../ui/auditorium'

const PLAYABLE_WITHIN_MS = 5000
const SNIFF_BYTES = 1 << 20
const SOUND_CHECK_MS = 2000

/** The first megabyte, read once: the container and codec tags for the No Print card. */
export const sniffHead = async (file: File): Promise<PrintSniff> =>
  sniffPrint(new Uint8Array(await file.slice(0, SNIFF_BYTES).arrayBuffer()), file.name)

/** The moviehash (two 64 KiB reads), or null for a file under 128 KiB or one that vanished. */
export async function hashOf(file: File): Promise<MovieHash | null> {
  try {
    return await osHash(file)
  } catch (e) {
    // < 128 KiB or unreadable: SILENT. "3" completes and "2" searches by name.
    if (!isFileTooSmall(e) && !(e instanceof HashUnavailable)) throw e
    return null
  }
}

/** The print is projectable when metadata arrives with a picture (or at least sound). */
export function playable(video: HTMLVideoElement): Promise<boolean> {
  return new Promise((resolve) => {
    const done = (ok: boolean) => {
      clearTimeout(timer)
      video.removeEventListener('loadedmetadata', onMeta)
      video.removeEventListener('error', onError)
      resolve(ok)
    }
    const onMeta = () => done(video.videoWidth > 0 || video.duration > 0)
    const onError = () => done(false)
    const timer = setTimeout(() => done(video.readyState >= 1), PLAYABLE_WITHIN_MS)
    if (video.readyState >= 1) {
      onMeta()
      return
    }
    video.addEventListener('loadedmetadata', onMeta)
    video.addEventListener('error', onError)
  })
}

interface MediaProbe {
  mozHasAudio?: boolean
  webkitAudioDecodedByteCount?: number
  audioTracks?: { length: number }
}

/** Does the element actually produce sound? null when the browser cannot say. */
function hasAudio(v: HTMLVideoElement): boolean | null {
  const p = v as HTMLVideoElement & MediaProbe
  if (typeof p.mozHasAudio === 'boolean') return p.mozHasAudio
  if (typeof p.webkitAudioDecodedByteCount === 'number') return p.webkitAudioDecodedByteCount > 0
  if (p.audioTracks) return p.audioTracks.length > 0
  return null
}

/**
 * A print that plays can still be silent (AC-3 / DTS / E-AC-3 in an MKV) or blind (HEVC in a
 * browser without it). Say so once, without stopping the film.
 */
export function checkPictureAndSound(
  video: HTMLVideoElement,
  sniff: PrintSniff,
  cap: Capability,
  stillOpen: () => boolean,
  notice: (text: string, link: NoticeLink) => void,
  link: NoticeLink,
): void {
  if (video.videoWidth === 0 && sniff.video) {
    const missing = noPrintReason({ ...sniff, audio: null }, cap).missing
    notice(
      `No picture: this browser has no ${missing ?? sniff.video} decoder, so only the sound plays.`,
      link,
    )
  }
  if (!sniff.audio) return
  const missing = noPrintReason({ ...sniff, video: null }, cap).missing
  const check = () => {
    if (!stillOpen()) return
    const audible = hasAudio(video)
    if (audible === true || (audible === null && missing === null)) return
    notice(
      missing
        ? `No sound: this browser has no ${missing} decoder.`
        : "No sound: this browser can't decode this film's audio.",
      link,
    )
  }
  const later = () => setTimeout(check, SOUND_CHECK_MS)
  if (!video.paused && video.readyState >= 3) later()
  else video.addEventListener('playing', later, { once: true })
}
