import { describe, expect, test } from 'vitest'
import { decodeSubtitle, parseSidecar, sidecarKind, vttAsSrt } from './sidecar'

const bytes = (...b: number[]) => new Uint8Array(b)
const utf16le = (s: string) => {
  const out = [0xff, 0xfe]
  for (const ch of s) {
    const c = ch.charCodeAt(0)
    out.push(c & 0xff, c >> 8)
  }
  return new Uint8Array(out)
}

describe('sidecar subtitles', () => {
  test('names the kind of a subtitle file and rejects a film', () => {
    expect(sidecarKind('Film.en.SRT')).toBe('srt')
    expect(sidecarKind('film.vtt')).toBe('vtt')
    expect(sidecarKind('film.ass')).toBe('ass')
    expect(sidecarKind('film.ssa')).toBe('ass')
    expect(sidecarKind('film.mkv')).toBeNull()
  })

  test('decodes strict UTF-8 and drops a UTF-8 BOM', () => {
    const cafe = new TextEncoder().encode('café')
    expect(decodeSubtitle(cafe)).toBe('café')
    expect(decodeSubtitle(new Uint8Array([0xef, 0xbb, 0xbf, ...cafe]))).toBe('café')
  })

  test('honours UTF-16 byte order marks', () => {
    expect(decodeSubtitle(utf16le('Hé'))).toBe('Hé')
    expect(decodeSubtitle(bytes(0xfe, 0xff, 0x00, 0x48, 0x00, 0xe9))).toBe('Hé')
  })

  test('falls back to windows-1252 when the bytes are not UTF-8', () => {
    // "café “x”" in windows-1252: é = 0xE9, curly quotes = 0x93 / 0x94.
    expect(decodeSubtitle(bytes(0x63, 0x61, 0x66, 0xe9, 0x20, 0x93, 0x78, 0x94))).toBe('café “x”')
  })

  test('reads WebVTT with hour-less timestamps, settings and notes', () => {
    const vtt = [
      'WEBVTT',
      '',
      'NOTE a comment',
      'over two lines',
      '',
      'intro',
      '00:01.000 --> 00:02.500 align:start line:90%',
      'Hello',
      '',
      '01:00:03.000 --> 01:00:04.000',
      '<i>World</i>',
    ].join('\n')
    expect(vttAsSrt(vtt)).toBe(
      '00:00:01.000 --> 00:00:02.500\nHello\n\n01:00:03.000 --> 01:00:04.000\n<i>World</i>',
    )
    const cues = parseSidecar('vtt', vtt)
    expect(cues?.map((c) => [c.start, c.end, c.text])).toEqual([
      [1000, 2500, 'Hello'],
      [3_603_000, 3_604_000, '<i>World</i>'],
    ])
  })

  test('parses SRT and leaves ASS to libass', () => {
    expect(parseSidecar('srt', '1\n00:00:01,000 --> 00:00:02,000\nHi\n')?.[0]?.text).toBe('Hi')
    expect(parseSidecar('ass', '[Script Info]')).toBeNull()
  })
})
