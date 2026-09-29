import { existsSync, readFileSync } from 'node:fs'
import { describe, expect, test } from 'vitest'
import { CHUNK, type HashSource, HashUnavailable, isFileTooSmall, osHash } from './osHash'

const filled = (size: number, byte: number) => new Blob([new Uint8Array(size).fill(byte)])

/** A stub source that reports any size and counts the bytes actually read. */
function stub(size: number, fill = 0): HashSource & { bytesRead: number; offsets: number[] } {
  const s = {
    size,
    bytesRead: 0,
    offsets: [] as number[],
    slice(start: number, end = size) {
      s.offsets.push(start)
      const len = end - start
      s.bytesRead += len
      return { arrayBuffer: async () => new Uint8Array(len).fill(fill).buffer }
    },
  }
  return s
}

// V1: the published vector. make-fixtures.sh downloads it to a temp dir; it is never committed.
const breakdance = process.env.BREAKDANCE_AVI ?? ''
const haveBreakdance = breakdance !== '' && existsSync(breakdance)
if (!haveBreakdance) {
  process.stderr.write('warning: BREAKDANCE_AVI not set — skipping the published vector V1\n')
}

describe('osHash', () => {
  test.skipIf(!haveBreakdance)('matches the published breakdance.avi vector', async () => {
    const bytes = readFileSync(breakdance)
    expect(await osHash(new Blob([bytes]))).toBe('8e245d9679d31e12')
  })

  test('pads the hash to 16 hex digits and accepts exactly 128 KiB', async () => {
    expect(await osHash(filled(131072, 0x00))).toBe('0000000000020000')
  })

  test('wraps the chunk sums as unsigned 64-bit', async () => {
    expect(await osHash(filled(131072, 0xff))).toBe('000000000001c000')
  })

  test('reads the tail chunk from an unaligned offset', async () => {
    const src = stub(200000)
    expect(await osHash(src)).toBe('0000000000030d40')
    expect(src.offsets).toContain(200000 - CHUNK)
  })

  test('rejects a file one byte under 128 KiB as too small', async () => {
    const err = await osHash(filled(131071, 0)).catch((e: unknown) => e)
    expect(err).toBeInstanceOf(RangeError)
    expect((err as Error).message).toBe('FILE_TOO_SMALL')
    expect(isFileTooSmall(err)).toBe(true)
    expect(isFileTooSmall(new Error('other'))).toBe(false)
  })

  test('keeps 64-bit precision for a 4 GiB file', async () => {
    expect(await osHash(stub(4294967296))).toBe('0000000100000000')
  })

  test('reads exactly 131072 bytes from a 4 GiB file', async () => {
    const src = stub(4 * 1024 ** 3)
    await osHash(src)
    expect(src.bytesRead).toBe(131072)
  })

  test('formats a hash with the top bit set without a sign or prefix', async () => {
    const bytes = new Uint8Array(131072)
    bytes[7] = 0x80
    const h = await osHash(new Blob([bytes]))
    expect(h).toBe('8000000000020000')
    expect(h).toMatch(/^[0-9a-f]{16}$/)
  })

  test('wraps a failed read as hash unavailable', async () => {
    const gone: HashSource = {
      size: 200000,
      slice: () => ({ arrayBuffer: () => Promise.reject(new Error('NotFoundError')) }),
    }
    await expect(osHash(gone)).rejects.toBeInstanceOf(HashUnavailable)
  })

  test('wraps a short read as hash unavailable', async () => {
    const short: HashSource = {
      size: 200000,
      slice: () => ({ arrayBuffer: async () => new ArrayBuffer(10) }),
    }
    await expect(osHash(short)).rejects.toBeInstanceOf(HashUnavailable)
  })
})
