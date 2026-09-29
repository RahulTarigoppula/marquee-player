// OpenSubtitles moviehash (IMPLEMENTATION-PROMPT §6.2).
// hash = (fileSize + Σ le_u64(first 64 KiB) + Σ le_u64(last 64 KiB)) mod 2⁶⁴
// JS numbers cannot hold 64 bits, so BigInt + an explicit mask.
// Blob.slice() + arrayBuffer() reads ONLY the two chunks; a 40 GB file never enters memory.
import type { MovieHash } from './types'

export const CHUNK = 65536
export const MIN_SIZE = 2 * CHUNK // 131072 — the service rejects anything smaller
const MASK = 0xffff_ffff_ffff_ffffn

/** The source vanished or failed between open and read. Threading skips to a filename search. */
export class HashUnavailable extends Error {
  override readonly name = 'HashUnavailable'
  constructor(readonly reason: unknown) {
    super('HASH_UNAVAILABLE')
  }
}

/** Anything with a size and a slice — a File, a Blob, or a test stub. */
export interface HashSource {
  readonly size: number
  slice(start: number, end?: number): { arrayBuffer(): Promise<ArrayBuffer> }
}

async function chunkSum(src: HashSource, offset: number): Promise<bigint> {
  let buf: ArrayBuffer
  try {
    buf = await src.slice(offset, offset + CHUNK).arrayBuffer()
  } catch (e) {
    throw new HashUnavailable(e)
  }
  if (buf.byteLength !== CHUNK) throw new HashUnavailable(new Error(`short read at ${offset}`))
  const dv = new DataView(buf)
  let s = 0n
  for (let i = 0; i < CHUNK; i += 8) s = (s + dv.getBigUint64(i, true)) & MASK
  return s
}

/** Rejects with RangeError('FILE_TOO_SMALL') under 128 KiB — a branch, never an error UI. */
export async function osHash(file: HashSource): Promise<MovieHash> {
  if (file.size < MIN_SIZE) throw new RangeError('FILE_TOO_SMALL')
  // The tail offset is NOT aligned to a chunk boundary.
  const [head, tail] = await Promise.all([chunkSum(file, 0), chunkSum(file, file.size - CHUNK)])
  const h = (BigInt(file.size) + head + tail) & MASK
  return h.toString(16).padStart(16, '0') as MovieHash
}

export function isFileTooSmall(e: unknown): boolean {
  return e instanceof RangeError && e.message === 'FILE_TOO_SMALL'
}
