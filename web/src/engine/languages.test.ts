import { describe, expect, test } from 'vitest'
import { defaultLanguage, languageLabel, subtitleCode } from './languages'

describe('subtitle languages', () => {
  test('maps browser language tags to OpenSubtitles codes', () => {
    expect(subtitleCode('en-US')).toBe('en')
    expect(subtitleCode('pt-BR')).toBe('pt-br')
    expect(subtitleCode('pt')).toBe('pt-pt')
    expect(subtitleCode('zh-Hant-TW')).toBe('zh-tw')
    expect(subtitleCode('zh')).toBe('zh-cn')
    expect(subtitleCode('nb-NO')).toBe('no')
    expect(subtitleCode('tlh')).toBeNull()
  })

  test('defaults to the first searchable browser language, else English', () => {
    expect(defaultLanguage(['tlh', 'hi-IN', 'en'])).toBe('hi')
    expect(defaultLanguage([])).toBe('en')
  })

  test('labels a code in plain words', () => {
    expect(languageLabel('pt-br')).toBe('Portuguese (Brazil)')
    expect(languageLabel('xx')).toBe('XX')
  })
})
