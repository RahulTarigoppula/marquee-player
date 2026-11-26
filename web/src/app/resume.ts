// "Resumed from 1:02:13": where each film was left, keyed by its moviehash (or name and size
// when it has none), saved every few seconds while it plays and whenever it stops, seeks while
// paused, or the page goes away.
import * as idb from '../storage/idb'

const RESUME_MIN_S = 30 // nearer the start than this, a film simply starts again
const RESUME_TAIL_S = 120 // within the last two minutes, the film counts as watched
const RESUME_SAVE_MS = 5000

export interface ResumeView {
  /** A film is open: offer its last position once the metadata is in. */
  start(key: string): void
  /** Save now and forget the film (it is closing). */
  stop(): void
}

export function resumeKeeper(
  video: HTMLVideoElement,
  offer: (at: number, onStartOver: () => void) => void,
): ResumeView {
  let key: string | null = null
  let lastSave = 0

  const save = (force = false) => {
    if (!key || !Number.isFinite(video.duration) || video.duration <= 0) return
    const t = performance.now()
    if (!force && t - lastSave < RESUME_SAVE_MS) return
    lastSave = t
    const position = video.currentTime
    if (position > video.duration - RESUME_TAIL_S || video.ended) {
      void idb.resume.clear(key).catch(() => undefined)
    } else if (position >= RESUME_MIN_S) {
      void idb.resume
        .put(key, { position, duration: video.duration, savedAt: Date.now() })
        .catch(() => undefined)
    }
  }

  video.addEventListener('timeupdate', () => save())
  video.addEventListener('pause', () => save(true))
  video.addEventListener('ended', () => save(true))
  // A seek while paused fires no timeupdate worth waiting for: keep the new place at once.
  video.addEventListener('seeked', () => {
    if (video.paused) save(true)
  })
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') save(true)
  })
  window.addEventListener('pagehide', () => save(true))

  return {
    start(k) {
      key = k
      void (async () => {
        const point = await idb.resume.get(k).catch(() => undefined)
        if (!point || key !== k) return
        const apply = () => {
          if (key !== k) return
          const dur = Number.isFinite(video.duration) ? video.duration : point.duration
          if (point.position < RESUME_MIN_S || point.position > dur - RESUME_TAIL_S) return
          if (video.currentTime > RESUME_MIN_S) return // the viewer already moved on
          video.currentTime = point.position
          offer(point.position, () => {
            video.currentTime = 0
            void idb.resume.clear(k).catch(() => undefined)
          })
        }
        if (video.readyState >= 1) apply()
        else video.addEventListener('loadedmetadata', apply, { once: true })
      })()
    },
    stop() {
      save(true)
      key = null
    },
  }
}
