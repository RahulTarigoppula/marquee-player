import { describe, expect, test } from 'vitest'
import download406 from '../../../test/fixtures/os/download-406.json'
import downloadOk from '../../../test/fixtures/os/download-ok.json'
import loginOk from '../../../test/fixtures/os/login-ok.json'
import searchByName from '../../../test/fixtures/os/search-by-name.json'
import hashHit from '../../../test/fixtures/os/search-hash-hit.json'
import {
  candidatesFromSearch,
  createApi,
  type FetchLike,
  failureOf,
  hashSearchParams,
  nameSearchParams,
  sortedQuery,
} from './api'
import { parseName } from './filename'
import type { MovieHash, OsSearchResponse, ParsedName } from './types'

const BASE = 'http://localhost:8787/api'
const HASH = '8e245d9679d31e12' as MovieHash

interface Call {
  url: string
  init: RequestInit | undefined
}

function fake(respond: (url: string) => Response | Promise<Response>) {
  const calls: Call[] = []
  const f: FetchLike = async (url, init) => {
    calls.push({ url, init })
    return respond(url)
  }
  return { calls, f }
}

const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  })

describe('worker client', () => {
  test('sorts query parameters alphabetically and drops empty ones', () => {
    expect(
      sortedQuery({ query: 'x', languages: 'en', year: null, episode_number: undefined, b: '' }),
    ).toBe('languages=en&query=x')
    expect(sortedQuery({ order_by: 'download_count', moviehash: HASH, languages: 'en' })).toBe(
      'languages=en&moviehash=8e245d9679d31e12&order_by=download_count',
    )
    expect(sortedQuery({ a: 1, a2: 2 })).toBe('a=1&a2=2')
  })

  test('searches by hash through the worker with sorted params and no key', async () => {
    const { calls, f } = fake(() => json(hashHit))
    const api = createApi({ base: BASE, fetch: f, jwt: () => null })
    const r = await api.search(hashSearchParams(HASH, ['en']))
    expect(r.ok).toBe(true)
    expect(calls[0]?.url).toBe(
      `${BASE}/subtitles?languages=en&moviehash=8e245d9679d31e12&moviehash_match=include&order_by=download_count`,
    )
    expect(JSON.stringify(calls[0]?.init ?? {})).not.toMatch(/api-key/i)
  })

  test('searches by the parsed name, or by the raw filename when confidence is low', () => {
    const p = parseName('Severance.S02E04.1080p.WEB.H264-NTb.mkv') as ParsedName
    expect(sortedQuery(nameSearchParams(p, ['en']))).toBe(
      'episode_number=4&languages=en&query=Severance&season_number=2',
    )
    const low = parseName('movie.mkv') as ParsedName
    expect(sortedQuery(nameSearchParams(low, ['en', 'hi']))).toBe(
      'languages=en%2Chi&query=movie.mkv',
    )
  })

  test('maps search results to candidates and treats an absent moviehash_match as false', () => {
    const hit = candidatesFromSearch(hashHit as OsSearchResponse)
    expect(hit[0]).toMatchObject({ id: '1234567', moviehashMatch: true, downloadCount: 12431 })
    const byName = candidatesFromSearch(searchByName as OsSearchResponse)
    expect(byName.every((c) => !c.moviehashMatch)).toBe(true)
    expect(byName[1]?.machineTranslated).toBe(true)
    const noFiles = {
      ...hashHit,
      data: [
        {
          ...hashHit.data[0],
          attributes: { ...hashHit.data[0]?.attributes, files: [], language: null },
        },
      ],
    } as OsSearchResponse
    expect(candidatesFromSearch(noFiles)).toEqual([])
  })

  test('downloads with the bearer token and asks for srt', async () => {
    const { calls, f } = fake(() => json(downloadOk))
    const api = createApi({ base: BASE, fetch: f, jwt: () => loginOk.token })
    const r = await api.download(1234567)
    expect(r).toEqual({ ok: true, value: downloadOk })
    expect(calls[0]?.url).toBe(`${BASE}/download`)
    expect(calls[0]?.init?.method).toBe('POST')
    expect(calls[0]?.init?.headers).toMatchObject({ Authorization: `Bearer ${loginOk.token}` })
    expect(JSON.parse(String(calls[0]?.init?.body))).toEqual({
      file_id: 1234567,
      sub_format: 'srt',
    })
  })

  test('maps a signed-out download to unauthorized with the sign-in sentence', async () => {
    const { f, calls } = fake(() =>
      json(
        {
          error: 'sign-in-required',
          sentence: 'Sign in to OpenSubtitles at the ticket office to download subtitles here.',
        },
        401,
      ),
    )
    const r = await createApi({ base: BASE, fetch: f, jwt: () => null }).download(1)
    expect(r).toMatchObject({ ok: false, failure: 'unauthorized', status: 401 })
    expect(!r.ok && r.sentence).toBe(
      'Sign in to OpenSubtitles at the ticket office to download subtitles here.',
    )
    expect(calls[0]?.init?.headers).not.toHaveProperty('Authorization')
  })

  test('maps an expired token to unauthorized with the ticket-expired sentence', async () => {
    const r = await failureOf(json({ message: 'You must be logged in', status: 401 }, 401))
    expect(r).toMatchObject({
      failure: 'unauthorized',
      sentence: 'Ticket expired — sign in again.',
    })
  })

  test('maps a 406 to quota exhausted and keeps the reset instant', async () => {
    const r = await failureOf(json(download406, 406))
    expect(r).toMatchObject({
      failure: 'quota-exhausted',
      sentence: 'No tickets left tonight — sign in for more, or use the Subdl slot.',
      download: { remaining: 0, requests: 10, reset_time_utc: '2026-09-07T00:00:00.000Z' },
    })
    const bare = await failureOf(new Response('nope', { status: 406 }))
    expect(bare.download).toBeUndefined()
  })

  test('maps a 410 to an expired link', async () => {
    const r = await failureOf(new Response('This link has expired', { status: 410 }))
    expect(r).toMatchObject({
      failure: 'link-expired',
      sentence: 'That print expired — fetching a fresh link.',
    })
  })

  test('maps a 429 to rate limited and honours Retry-After', async () => {
    const r = await failureOf(
      json({ message: 'Throttle limit reached. Retry later.' }, 429, { 'Retry-After': '2' }),
    )
    expect(r).toMatchObject({
      failure: 'rate-limited',
      retryAfterSeconds: 2,
      sentence: 'OpenSubtitles asked us to wait 2 s.',
    })
    const worker = await failureOf(
      json({ error: 'rate-limited', sentence: 'Too many', retryAfterSeconds: 60 }, 429),
    )
    expect(worker.retryAfterSeconds).toBe(60)
    const none = await failureOf(new Response('', { status: 429 }))
    expect(none.retryAfterSeconds).toBe(2)
  })

  test('maps a failed fetch to offline with the offline sentence', async () => {
    const api = createApi({
      base: BASE,
      fetch: () => Promise.reject(new TypeError('Failed to fetch')),
      jwt: () => null,
    })
    expect(await api.search({ query: 'x' })).toMatchObject({
      ok: false,
      failure: 'offline',
      sentence: "You're offline — playing without new subtitles.",
    })
  })

  test('maps an aborted request to cancelled', async () => {
    const api = createApi({
      base: BASE,
      fetch: () => Promise.reject(new DOMException('aborted', 'AbortError')),
      jwt: () => null,
    })
    expect(await api.search({ query: 'x' }, new AbortController().signal)).toMatchObject({
      failure: 'cancelled',
    })
  })

  test('prints the worker sentence for a rejected origin and upstream errors', async () => {
    const r = await failureOf(
      json(
        {
          error: 'forbidden-origin',
          sentence: "This build isn't allowed to talk to the subtitle service.",
        },
        403,
      ),
    )
    expect(r.sentence).toBe("This build isn't allowed to talk to the subtitle service.")
    const bad = await failureOf(new Response('<html>', { status: 502 }))
    expect(bad).toMatchObject({ failure: 'offline', status: 502 })
    const plain403 = await failureOf(new Response('', { status: 403 }))
    expect(plain403.failure).toBe('offline')
  })

  test('fetches the temporary link through the subtitle-file route', async () => {
    const { calls, f } = fake(() => new Response('1\n00:00:01,000 --> 00:00:02,000\nHi\n'))
    const api = createApi({ base: BASE, fetch: f, jwt: () => null })
    const r = await api.subtitleFile(downloadOk.link, new AbortController().signal)
    expect(r.ok && r.value).toContain('Hi')
    expect(calls[0]?.url).toBe(`${BASE}/subtitle-file?link=${encodeURIComponent(downloadOk.link)}`)
  })

  test('logs in with the body sorted and reads user info with the token', async () => {
    const { calls, f } = fake((url) =>
      url.endsWith('/login') ? json(loginOk) : json({ data: {} }),
    )
    const api = createApi({ base: BASE, fetch: f, jwt: () => 'jwt' })
    const r = await api.login('rahul', 'pw')
    expect(r.ok && r.value.user.allowed_downloads).toBe(20)
    await api.userInfo()
    expect(calls[1]?.init?.headers).toEqual({ Authorization: 'Bearer jwt' })
  })

  test('maps an unreadable success body to offline', async () => {
    const { f } = fake(() => new Response('not json', { status: 200 }))
    const r = await createApi({ base: BASE, fetch: f, jwt: () => null }).search({ query: 'x' })
    expect(r).toMatchObject({ ok: false, failure: 'offline' })
  })
})
