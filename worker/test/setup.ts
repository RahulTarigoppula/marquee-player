// Stands in for the Workers runtime's `caches.default` (the Cache API) under Node.
// Only match/put/delete are used by the Worker's per-IP counter.
class MemoryCache {
  private store = new Map<string, Response>()

  async match(req: Request | string): Promise<Response | undefined> {
    const r = this.store.get(typeof req === 'string' ? req : req.url)
    return r?.clone()
  }

  async put(req: Request | string, res: Response): Promise<void> {
    this.store.set(typeof req === 'string' ? req : req.url, res.clone())
  }

  async delete(req: Request | string): Promise<boolean> {
    return this.store.delete(typeof req === 'string' ? req : req.url)
  }
}

Object.defineProperty(globalThis, 'caches', {
  value: { default: new MemoryCache() },
  configurable: true,
  writable: true,
})
