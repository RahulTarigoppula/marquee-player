// Subtitle languages (web-only). OpenSubtitles speaks ISO 639-1 plus a few regional codes
// (pt-br / pt-pt, zh-cn / zh-tw). Pure: the browser's language list is passed in.

export interface SubtitleLanguage {
  code: string
  name: string
}

export const LANGUAGES: readonly SubtitleLanguage[] = [
  { code: 'en', name: 'English' },
  { code: 'ar', name: 'Arabic' },
  { code: 'bn', name: 'Bengali' },
  { code: 'bg', name: 'Bulgarian' },
  { code: 'zh-cn', name: 'Chinese (simplified)' },
  { code: 'zh-tw', name: 'Chinese (traditional)' },
  { code: 'hr', name: 'Croatian' },
  { code: 'cs', name: 'Czech' },
  { code: 'da', name: 'Danish' },
  { code: 'nl', name: 'Dutch' },
  { code: 'fi', name: 'Finnish' },
  { code: 'fr', name: 'French' },
  { code: 'de', name: 'German' },
  { code: 'el', name: 'Greek' },
  { code: 'he', name: 'Hebrew' },
  { code: 'hi', name: 'Hindi' },
  { code: 'hu', name: 'Hungarian' },
  { code: 'id', name: 'Indonesian' },
  { code: 'it', name: 'Italian' },
  { code: 'ja', name: 'Japanese' },
  { code: 'kn', name: 'Kannada' },
  { code: 'ko', name: 'Korean' },
  { code: 'ms', name: 'Malay' },
  { code: 'ml', name: 'Malayalam' },
  { code: 'mr', name: 'Marathi' },
  { code: 'no', name: 'Norwegian' },
  { code: 'fa', name: 'Persian' },
  { code: 'pl', name: 'Polish' },
  { code: 'pt-pt', name: 'Portuguese' },
  { code: 'pt-br', name: 'Portuguese (Brazil)' },
  { code: 'ro', name: 'Romanian' },
  { code: 'ru', name: 'Russian' },
  { code: 'sr', name: 'Serbian' },
  { code: 'sk', name: 'Slovak' },
  { code: 'sl', name: 'Slovenian' },
  { code: 'es', name: 'Spanish' },
  { code: 'sv', name: 'Swedish' },
  { code: 'ta', name: 'Tamil' },
  { code: 'te', name: 'Telugu' },
  { code: 'th', name: 'Thai' },
  { code: 'tr', name: 'Turkish' },
  { code: 'uk', name: 'Ukrainian' },
  { code: 'ur', name: 'Urdu' },
  { code: 'vi', name: 'Vietnamese' },
]

const KNOWN = new Set(LANGUAGES.map((l) => l.code))

/** A BCP 47 tag (en-US, pt-BR, zh-Hant-TW, nb) → the OpenSubtitles code, or null. */
export function subtitleCode(tag: string): string | null {
  const t = tag.trim().toLowerCase()
  const [base = ''] = t.split('-')
  let code: string = base
  if (base === 'pt') code = /-br\b/.test(t) ? 'pt-br' : 'pt-pt'
  else if (base === 'zh') code = /-(tw|hk|mo|hant)\b/.test(t) ? 'zh-tw' : 'zh-cn'
  else if (base === 'nb' || base === 'nn') code = 'no'
  else if (base === 'iw') code = 'he'
  else if (base === 'in') code = 'id'
  return KNOWN.has(code) ? code : null
}

/** The first browser language we can search for, else English. */
export function defaultLanguage(tags: readonly string[]): string {
  for (const t of tags) {
    const c = subtitleCode(t)
    if (c) return c
  }
  return 'en'
}

export const languageLabel = (code: string): string =>
  LANGUAGES.find((l) => l.code === code)?.name ?? code.toUpperCase()
