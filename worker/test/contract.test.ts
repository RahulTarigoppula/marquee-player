// Live contract test (IMPLEMENTATION-PROMPT §10.8). Nightly, never blocking; skipped without a key.
// Search-only: search is unlimited. The single /download probe runs only with RUN_DOWNLOAD_PROBE=1
// (at most once a month). It asserts that every field the fixtures rely on still exists and records
// the observed X-RateLimit-* values into test/observed-limits.json. CI turns a failure into a
// `gh issue create`, not a red branch.
import { describe, expect, it } from 'vitest'
import searchHit from './fixtures/search-hash-hit.json'

const penv = (globalThis as unknown as { process: { env: Record<string, string | undefined> } })
  .process.env
const KEY = penv.OS_API_KEY
const DOWNLOAD_PROBE = penv.RUN_DOWNLOAD_PROBE === '1'
const BASE = 'https://api.opensubtitles.com/api/v1'
const UA = 'Marquee-Contract v1.0.0'
const HASH = '8e245d9679d31e12'

const observed: Record<string, unknown> = { at: new Date().toISOString() }

function headers(): Record<string, string> {
  return { 'Api-Key': KEY ?? '', 'User-Agent': UA, Accept: 'application/json' }
}

async function get(
  pathAndQuery: string,
  redirect: 'follow' | 'manual' = 'follow',
): Promise<Response> {
  return fetch(BASE + pathAndQuery, { headers: headers(), redirect })
}

function limits(res: Response): Record<string, string | null> {
  return {
    status: String(res.status),
    limit: res.headers.get('X-RateLimit-Limit'),
    remaining: res.headers.get('X-RateLimit-Remaining'),
    reset: res.headers.get('X-RateLimit-Reset'),
    retryAfter: res.headers.get('Retry-After'),
  }
}

type Json = Record<string, unknown>

function expectType(obj: Json, key: string, types: string[]): void {
  expect(obj, `missing field ${key}`).toHaveProperty(key)
  const v = obj[key]
  const t = v === null ? 'null' : Array.isArray(v) ? 'array' : typeof v
  expect(types, `${key} is ${t}`).toContain(t)
}

// The fields the fixtures (and therefore the client parsers) read from a search item.
function expectSearchItemShape(item: Json): void {
  expectType(item, 'id', ['string'])
  expectType(item, 'type', ['string'])
  expectType(item, 'attributes', ['object'])
  const a = item.attributes as Json
  expectType(a, 'language', ['string'])
  expectType(a, 'download_count', ['number'])
  expectType(a, 'hearing_impaired', ['boolean'])
  expectType(a, 'machine_translated', ['boolean'])
  expectType(a, 'ai_translated', ['boolean'])
  expectType(a, 'fps', ['number'])
  expectType(a, 'release', ['string', 'null'])
  expectType(a, 'upload_date', ['string'])
  expectType(a, 'files', ['array'])
  const f = (a.files as Json[])[0]
  expect(f, 'attributes.files[0]').toBeDefined()
  expectType(f as Json, 'file_id', ['number'])
  expectType(f as Json, 'cd_number', ['number', 'null'])
  expectType(f as Json, 'file_name', ['string', 'null'])
  expectType(a, 'feature_details', ['object'])
  const fd = a.feature_details as Json
  expectType(fd, 'feature_type', ['string'])
  expectType(fd, 'title', ['string'])
  expectType(fd, 'year', ['number', 'null'])
  expectType(fd, 'imdb_id', ['number', 'null'])
  expectType(fd, 'tmdb_id', ['number', 'null'])
}

async function writeObserved(): Promise<void> {
  const fs = (await import(/* @vite-ignore */ 'node:fs/promises' as string)) as {
    writeFile(path: URL, data: string): Promise<void>
  }
  await fs.writeFile(
    new URL('./observed-limits.json', import.meta.url),
    `${JSON.stringify(observed, null, 2)}\n`,
  )
}

describe.skipIf(!KEY)('OpenSubtitles live contract', () => {
  it('the fixture itself still has the shape this test asserts', () => {
    expectSearchItemShape(searchHit.data[0] as unknown as Json)
  })

  it('search by imdb_id returns the fields the fixtures rely on', async () => {
    const res = await get('/subtitles?imdb_id=41959&languages=en')
    observed.search = limits(res)
    expect(res.status).toBe(200)
    const body = (await res.json()) as Json
    for (const k of ['total_pages', 'total_count', 'per_page', 'page']) {
      expectType(body, k, ['number'])
    }
    expectType(body, 'data', ['array'])
    const data = body.data as Json[]
    expect(data.length).toBeGreaterThan(0)
    for (const item of data.slice(0, 5)) expectSearchItemShape(item)
  })

  it('a moviehash search carries moviehash_match on each item', async () => {
    const res = await get(`/subtitles?languages=en&moviehash=${HASH}&moviehash_match=include`)
    observed.hashSearch = limits(res)
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: Json[] }
    expect(Array.isArray(body.data)).toBe(true)
    for (const item of body.data.slice(0, 5)) {
      expectType(item.attributes as Json, 'moviehash_match', ['boolean'])
    }
  })

  it('records whether an unsorted query still 301s and drops moviehash_match (K3)', async () => {
    const res = await get(
      `/subtitles?moviehash_match=include&moviehash=${HASH}&languages=en`,
      'manual',
    )
    const location = res.headers.get('Location')
    observed.unsortedQuery = {
      status: res.status,
      location,
      dropsMoviehashMatch: location ? !location.includes('moviehash_match') : null,
    }
    expect([200, 301, 302, 307, 308]).toContain(res.status)
  })

  it('records whether moviehash_match=only is honoured', async () => {
    const res = await get(`/subtitles?languages=en&moviehash=${HASH}&moviehash_match=only`)
    expect(res.status).toBe(200)
    const body = (await res.json()) as { data: Json[] }
    observed.moviehashMatchOnly = {
      items: body.data.length,
      honoured: body.data.every((d) => (d.attributes as Json).moviehash_match === true),
    }
  })

  it('probes whether /utilities/guessit exists', async () => {
    const res = await get('/utilities/guessit?filename=The.Third.Man.1949.1080p.BluRay.x264.mkv')
    observed.guessit = { status: res.status }
    expect(res.status).toBeLessThan(500)
  })

  it.skipIf(!DOWNLOAD_PROBE)('one /download probe: link shape and quota fields', async () => {
    const search = await get('/subtitles?imdb_id=41959&languages=en')
    const fileId = ((await search.json()) as { data: Json[] }).data
      .map((d) => ((d.attributes as Json).files as Json[])[0]?.file_id)
      .find((id) => typeof id === 'number')
    expect(fileId).toBeTypeOf('number')
    const res = await fetch(`${BASE}/download`, {
      method: 'POST',
      headers: { ...headers(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ file_id: fileId }),
    })
    observed.download = limits(res)
    expect(res.status).toBe(200)
    const body = (await res.json()) as Json
    for (const k of ['link', 'file_name', 'message', 'reset_time', 'reset_time_utc']) {
      expectType(body, k, ['string'])
    }
    expectType(body, 'requests', ['number'])
    expectType(body, 'remaining', ['number'])
    expect(new URL(body.link as string).hostname).toMatch(/(^|\.)opensubtitles\.(com|org)$/)
    observed.downloadLink = { issuedAt: new Date().toISOString(), remaining: body.remaining }
  })

  it('writes the observed limits', async () => {
    await writeObserved()
  })
})
