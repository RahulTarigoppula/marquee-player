// Small per-browser preferences (volume, mute, subtitle language and size). localStorage, because
// they are needed synchronously at startup; every access is guarded (private windows, blocked
// storage) and a missing or malformed value falls back to the default.
const KEY = 'marquee.prefs.v1'

export interface Prefs {
  volume: number // 0..1
  muted: boolean
  language: string | null // OpenSubtitles code; null = from the browser
  cueSize: 'S' | 'M' | 'L'
}

const DEFAULTS: Prefs = { volume: 1, muted: false, language: null, cueSize: 'M' }

export function loadPrefs(): Prefs {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY) ?? '{}') as Partial<Prefs>
    return {
      volume:
        typeof raw.volume === 'number' && raw.volume >= 0 && raw.volume <= 1
          ? raw.volume
          : DEFAULTS.volume,
      muted: raw.muted === true,
      language: typeof raw.language === 'string' ? raw.language : null,
      cueSize: raw.cueSize === 'S' || raw.cueSize === 'L' ? raw.cueSize : 'M',
    }
  } catch {
    return { ...DEFAULTS }
  }
}

export function savePrefs(p: Prefs): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(p))
  } catch {
    // storage blocked: the preference lasts for this visit only
  }
}
