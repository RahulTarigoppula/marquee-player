import { describe, expect, test } from 'vitest'
import { isSubtitleName, parseName, parsePath } from './filename'
import type { ParsedName } from './types'

type Row = Partial<ParsedName>

/** Every unlisted field must be null (never ''), and flags false. */
const expectParsed = (name: string, want: Row) => {
  const got = parseName(name)
  expect(got).not.toBeNull()
  expect(got).toMatchObject({
    year: null,
    season: null,
    episode: null,
    resolution: null,
    source: null,
    videoCodecToken: null,
    group: null,
    remastered: false,
    raw: name,
    ...want,
  })
}

describe('filename grammar', () => {
  test('parses the house film with year, resolution, source, codec and group', () => {
    expectParsed('The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.mkv', {
      title: 'The Third Man',
      year: 1949,
      resolution: '1080p',
      source: 'BluRay',
      videoCodecToken: 'x264',
      group: 'AMIABLE',
      kind: 'movie',
      confidence: 'high',
    })
  })

  test('flags a remastered release and keeps the title before the flag', () => {
    expectParsed('Chungking.Express.1994.REMASTERED.1080p.BluRay.x265-RARBG.mkv', {
      title: 'Chungking Express',
      year: 1994,
      resolution: '1080p',
      source: 'BluRay',
      videoCodecToken: 'x265',
      group: 'RARBG',
      remastered: true,
    })
  })

  test('keeps a WEB-DL source whole and the H264 codec token verbatim', () => {
    expectParsed('Paddington.2014.720p.WEB-DL.H264-NTb.mkv', {
      title: 'Paddington',
      year: 2014,
      resolution: '720p',
      source: 'WEB-DL',
      videoCodecToken: 'H264',
      group: 'NTb',
    })
  })

  test('parses season and episode as an episode', () => {
    expectParsed('Severance.S02E04.1080p.WEB.H264-NTb.mkv', {
      title: 'Severance',
      season: 2,
      episode: 4,
      resolution: '1080p',
      source: 'WEB',
      videoCodecToken: 'H264',
      group: 'NTb',
      kind: 'episode',
      confidence: 'high',
    })
  })

  test('reads a year in parentheses from a name with spaces', () => {
    expectParsed('The Third Man (1949).mkv', {
      title: 'The Third Man',
      year: 1949,
      confidence: 'high',
    })
  })

  test('parses the anime bracket form and discards the trailing CRC', () => {
    expectParsed('[SubsPlease] Frieren - 12 (1080p) [ABCD1234].mkv', {
      title: 'Frieren',
      episode: 12,
      resolution: '1080p',
      group: 'SubsPlease',
      kind: 'episode',
      confidence: 'high',
    })
  })

  test('gives a bare name low confidence so the raw filename is searched', () => {
    expectParsed('movie.mkv', { title: 'movie', kind: 'movie', confidence: 'low' })
  })

  test('rejects a subtitle file as not a video', () => {
    expect(parseName('The.Third.Man.1949.1080p.BluRay.x264-AMIABLE.en.srt')).toBeNull()
    expect(isSubtitleName('sample.ass')).toBe(true)
    expect(isSubtitleName('film.mkv')).toBe(false)
  })

  test('does not steal a year that is part of the title', () => {
    expectParsed('Blade.Runner.2049.2017.2160p.UHD.BluRay.x265-TERMINAL.mkv', {
      title: 'Blade Runner 2049',
      year: 2017,
      resolution: '2160p',
      source: 'BluRay',
      videoCodecToken: 'x265',
      group: 'TERMINAL',
    })
  })

  test('treats a trailing codec after the last dash as a codec, not a group', () => {
    expectParsed('Arrival.2016.1080p.BluRay-x265.mkv', {
      title: 'Arrival',
      year: 2016,
      resolution: '1080p',
      source: 'BluRay',
      videoCodecToken: 'x265',
      group: null,
    })
  })

  test('parses a release name with a group glued to the source', () => {
    expectParsed('The.Third.Man.1949.BluRay-AMIABLE', {
      title: 'The Third Man',
      year: 1949,
      source: 'BluRay',
      group: 'AMIABLE',
    })
  })

  test('parses the 1x03 and Season Episode forms', () => {
    expect(parseName('Fargo 1x03 720p HDTV.mkv')).toMatchObject({
      title: 'Fargo',
      season: 1,
      episode: 3,
      source: 'HDTV',
    })
    expect(parseName('Fargo Season 2 Episode 5.mkv')).toMatchObject({
      title: 'Fargo',
      season: 2,
      episode: 5,
      kind: 'episode',
    })
  })

  test('gives a multi-word title with quality tokens but no year medium confidence', () => {
    expect(parseName('Some Great Film 1080p BluRay.mkv')).toMatchObject({
      title: 'Some Great Film',
      confidence: 'medium',
      proper: false,
    })
    expect(parseName('Film.PROPER.EXTENDED.720p.mkv')).toMatchObject({
      proper: true,
      extended: true,
    })
  })

  test('falls back to the parent directory when the basename is low confidence', () => {
    expect(parsePath('D:\\Films\\The Third Man (1949)\\video.mkv')).toMatchObject({
      title: 'The Third Man',
      year: 1949,
    })
    expect(parsePath('/films/video.mkv')).toMatchObject({ title: 'video', confidence: 'low' })
    expect(parsePath('The.Third.Man.1949.mkv')).toMatchObject({ title: 'The Third Man' })
  })
})
