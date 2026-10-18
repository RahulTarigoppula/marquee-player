// Public configuration only. The OpenSubtitles key lives in the Worker, never in a VITE_* var
// (that prefix is inlined verbatim into the public bundle).

// Dev with no setting → the local wrangler dev Worker. A build with no (or an empty) setting →
// no Worker: films still play, and adding a subtitle file is the way to get subtitles.
export const API_BASE: string =
  import.meta.env.VITE_API_BASE ?? (import.meta.env.DEV ? 'http://localhost:8787/api' : '')

/** Online subtitle search (and the ticket office) exist only when a Worker is configured. */
export const searchEnabled: boolean = API_BASE !== ''

export const APP_VERSION: string = import.meta.env.VITE_APP_VERSION ?? 'dev'

/** The project's own Releases page: where the Windows and Android builds live. */
export const PROJECT_RELEASES = 'https://github.com/RahulTarigoppula/marquee-player/releases/latest'

/** Free OpenSubtitles account sign-up (the Worker never creates accounts). */
export const SIGN_UP_URL = 'https://www.opensubtitles.com/en/users/sign_up'

/**
 * Where the native builds live. On GitHub Pages (https://<owner>.github.io/<repo>/) the
 * Releases page is derived from the URL itself; VITE_RELEASES_URL overrides it.
 */
export function releasesUrl(loc: Pick<Location, 'hostname' | 'pathname'>): string {
  const env = import.meta.env.VITE_RELEASES_URL
  if (env) return env
  const owner = /^([^.]+)\.github\.io$/.exec(loc.hostname)?.[1]
  const repo = loc.pathname.split('/').filter(Boolean)[0]
  return owner && repo ? `https://github.com/${owner}/${repo}/releases/latest` : PROJECT_RELEASES
}
