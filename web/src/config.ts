// Public configuration only. The OpenSubtitles key lives in the Worker, never in a VITE_* var
// (that prefix is inlined verbatim into the public bundle).

export const API_BASE: string = import.meta.env.VITE_API_BASE ?? 'http://localhost:8787/api'
export const APP_VERSION: string = import.meta.env.VITE_APP_VERSION ?? 'dev'

/**
 * Where the native builds live. On GitHub Pages (https://<owner>.github.io/<repo>/) the
 * Releases page is derived from the URL itself; VITE_RELEASES_URL overrides it.
 */
export function releasesUrl(loc: Pick<Location, 'hostname' | 'pathname'>): string {
  const env = import.meta.env.VITE_RELEASES_URL
  if (env) return env
  const owner = /^([^.]+)\.github\.io$/.exec(loc.hostname)?.[1]
  const repo = loc.pathname.split('/').filter(Boolean)[0] ?? 'marquee'
  return owner ? `https://github.com/${owner}/${repo}/releases/latest` : 'https://github.com/'
}
