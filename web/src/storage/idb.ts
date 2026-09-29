// A small promise wrapper over IndexedDB (no Dexie): one object store per entity.
//   subtitles  key `${hash}|${lang}` → CachedSubtitle (VTT already converted: offline reattach)
//   offsets    key hash              → StoredOffset
//   session    key 'session'         → StoredSession (the JWT SEALED, never plaintext)
//   keys       key 'jwt'             → a NON-EXTRACTABLE AES-GCM CryptoKey
import type { CachedSubtitle, LiteSession, MovieHash, StoredOffset } from '../engine/types'

const DB_NAME = 'marquee-lite'
const DB_VERSION = 1
type Store = 'subtitles' | 'offsets' | 'session' | 'keys'
const STORES: Store[] = ['subtitles', 'offsets', 'session', 'keys']

const req = <T>(r: IDBRequest<T>): Promise<T> =>
  new Promise((resolve, reject) => {
    r.onsuccess = () => resolve(r.result)
    r.onerror = () => reject(r.error)
  })

let db: Promise<IDBDatabase> | null = null

function open(): Promise<IDBDatabase> {
  if (!db) {
    const r = indexedDB.open(DB_NAME, DB_VERSION)
    r.onupgradeneeded = () => {
      for (const s of STORES)
        if (!r.result.objectStoreNames.contains(s)) r.result.createObjectStore(s)
    }
    db = req(r)
  }
  return db
}

async function tx<T>(
  store: Store,
  mode: IDBTransactionMode,
  run: (s: IDBObjectStore) => IDBRequest<T>,
): Promise<T> {
  const d = await open()
  return req(run(d.transaction(store, mode).objectStore(store)))
}

const get = <T>(store: Store, key: string) =>
  tx<T | undefined>(store, 'readonly', (s) => s.get(key))
const put = (store: Store, key: string, value: unknown) =>
  tx(store, 'readwrite', (s) => s.put(value, key))
const del = (store: Store, key: string) => tx(store, 'readwrite', (s) => s.delete(key))
const all = <T>(store: Store) => tx<T[]>(store, 'readonly', (s) => s.getAll())

export const subtitleKey = (hash: MovieHash, lang: string) => `${hash}|${lang}`

export const subtitles = {
  get: (hash: MovieHash, lang: string) => get<CachedSubtitle>('subtitles', subtitleKey(hash, lang)),
  put: (c: CachedSubtitle) => put('subtitles', subtitleKey(c.hash, c.language), c),
}

export const offsets = {
  all: () => all<StoredOffset>('offsets'),
  put: (o: StoredOffset) => (o.delayMs === 0 ? del('offsets', o.hash) : put('offsets', o.hash, o)),
}

// ── the session, with the JWT sealed by a non-extractable AES-GCM key ──

interface Sealed {
  iv: Uint8Array<ArrayBuffer>
  data: ArrayBuffer
}
type StoredSession = Omit<LiteSession, 'jwt'> & { sealed: Sealed | null; user: string | null }

async function jwtKey(): Promise<CryptoKey> {
  const existing = await get<CryptoKey>('keys', 'jwt')
  if (existing) return existing
  const key = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, [
    'encrypt',
    'decrypt',
  ])
  await put('keys', 'jwt', key) // structured-cloned; still non-extractable
  return key
}

const IV_BYTES = 12

export async function seal(jwt: string): Promise<Sealed> {
  const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES))
  const data = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    await jwtKey(),
    new TextEncoder().encode(jwt),
  )
  return { iv, data }
}

export async function unseal(s: Sealed): Promise<string> {
  const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: s.iv }, await jwtKey(), s.data)
  return new TextDecoder().decode(plain)
}

export interface LoadedSession {
  session: LiteSession
  user: string | null
}

export async function loadSession(): Promise<LoadedSession | null> {
  const s = await get<StoredSession>('session', 'session')
  if (!s) return null
  const { sealed, user, ...rest } = s
  let jwt: string | null = null
  if (sealed) jwt = await unseal(sealed).catch(() => null)
  return { session: { ...rest, jwt }, user }
}

/**
 * Persist the session. With `sessionOnly` the token stays in memory: the stored record keeps
 * the preferences and the quota, and no ticket is ever written to this device.
 */
export async function saveSession(
  s: LiteSession,
  user: string | null,
  sessionOnly: boolean,
): Promise<void> {
  const { jwt, ...rest } = s
  const sealed = jwt && !sessionOnly ? await seal(jwt) : null
  await put('session', 'session', {
    ...rest,
    sealed,
    user: sessionOnly ? null : user,
  } satisfies StoredSession)
}
