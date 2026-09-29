import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, expect, test } from 'vitest'
import { parseSrt, shiftCues, srtToVtt, toVtt, vttTime } from './srt2vtt'

const FIXTURES = join(dirname(fileURLToPath(import.meta.url)), '../../../test/fixtures')
const fixture = (name: string): string => readFileSync(join(FIXTURES, name), 'utf8')

describe('srt to vtt', () => {
  test('converts the BOM + CRLF fixture byte for byte', () => {
    expect(srtToVtt(fixture('sample-crlf-bom.srt'))).toBe(fixture('sample-crlf-bom.expected.vtt'))
  })

  test('sorts cues by start and renumbers them', () => {
    const cues = parseSrt(fixture('sample-crlf-bom.srt'))
    expect(cues.map((c) => c.start)).toEqual([1000, 62500])
    expect(toVtt(cues).split('\n')[2]).toBe('1')
  })

  test('shifts every cue by the delay', () => {
    const vtt = srtToVtt(fixture('sample-crlf-bom.srt'), 350)
    expect(vtt).toContain('00:00:01.350 --> 00:00:02.850')
    expect(vtt).toContain('00:01:02.850 --> 00:01:04.350')
  })

  test('clamps a negative shift at zero and keeps overlaps', () => {
    const cues = parseSrt(
      '1\n00:00:00,200 --> 00:00:01,000\nA\n\n2\n00:00:00,500 --> 00:00:02,000\nB\n',
    )
    const shifted = shiftCues(cues, -350)
    expect(shifted.map((c) => [c.start, c.end])).toEqual([
      [0, 650],
      [150, 1650],
    ])
    expect(toVtt(cues, -5000)).toContain('00:00:00.000 --> 00:00:00.000')
  })

  test('keeps italic, bold and underline tags and strips font tags to their text', () => {
    const cues = parseSrt(
      '1\n00:00:01,000 --> 00:00:02,000\n<font color="#ff0000"><b>Red</b></font> <u>u</u> <i>i</i>\n',
    )
    expect(cues[0]?.text).toBe('<b>Red</b> <u>u</u> <i>i</i>')
  })

  test('turns a leading an8 override into line 0', () => {
    const vtt = srtToVtt(fixture('sample.srt'))
    expect(vtt).toContain('00:00:07.000 --> 00:00:09.000 line:0\nTop of the frame.')
    expect(vtt).not.toContain('{\\an8}')
  })

  test('caps a cue at 10000 characters', () => {
    const long = 'x'.repeat(20_000)
    expect(parseSrt(`1\n00:00:01,000 --> 00:00:02,000\n${long}\n`)[0]?.text).toHaveLength(10_000)
  })

  test('ignores stray text outside a cue and a timing with no text', () => {
    const cues = parseSrt(
      'garbage\n\n1\n00:00:01,000 --> 00:00:02,000\n\n2\n00:00:03.5 --> 00:00:04,000\nok',
    )
    expect(cues).toHaveLength(1)
    expect(cues[0]?.start).toBe(3500)
  })

  test('formats VTT timestamps with milliseconds and unbounded hours', () => {
    expect(vttTime(0)).toBe('00:00:00.000')
    expect(vttTime(45_000_123)).toBe('12:30:00.123')
    expect(vttTime(-1)).toBe('00:00:00.000')
  })
})
