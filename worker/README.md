# marquee-proxy

The Cloudflare Worker that lets Marquee Lite talk to OpenSubtitles: it answers CORS preflights,
injects the `Api-Key` server-side, and proxies an allow-listed set of routes. It logs nothing and
stores nothing. Native builds never use it. The spec is IMPLEMENTATION-PROMPT §7.6; `src/index.ts`
is byte-identical to that listing and to DEPLOYMENT §4.3 — change all three together.

## Develop

```bash
npm ci
npm test               # test/worker.test.ts — every §7.6 invariant, upstream mocked
npx tsc --noEmit
npx biome ci .         # noConsole is an error here
npm run test:contract  # live API contract (§10.8); skipped unless OS_API_KEY is set
```

## Deploy

From `worker/`, once:

```bash
npx wrangler login
npx wrangler secret put OS_API_KEY        # paste the consumer key; write-only from here on
npx wrangler secret put TMDB_READ_TOKEN   # optional: turns on /api/tmdb/* (Lobby posters)
```

Set `ALLOWED_ORIGIN` in `wrangler.toml` to the Pages origin (`https://<owner>.github.io`, no path),
then:

```bash
npm run deploy
```

## Verify after deploy

```bash
W=https://marquee-proxy.<subdomain>.workers.dev

# 1. Preflight from the real origin -> 204 with CORS headers
curl -i -X OPTIONS "$W/api/subtitles" -H "Origin: https://<owner>.github.io" \
  -H "Access-Control-Request-Method: GET" -H "Access-Control-Request-Headers: authorization"

# 2. Wrong origin -> 403, and NO Access-Control-Allow-Origin in the response
curl -i -X OPTIONS "$W/api/subtitles" -H "Origin: https://evil.example"

# 3. No Origin at all -> 403 (native builds must not use the proxy)
curl -i "$W/api/subtitles?languages=en&moviehash=8e245d9679d31e12"

# 4. A real search from the real origin -> 200, and grep proves the key is not echoed
curl -s "$W/api/subtitles?languages=en&moviehash=8e245d9679d31e12&moviehash_match=include" \
  -H "Origin: https://<owner>.github.io" | tee /tmp/os.json | head -c 400
grep -c "$OS_API_KEY" /tmp/os.json     # must print 0

# 5. Path outside the allow-list -> 404 {"error":"not-found",...}
curl -i "$W/api/admin" -H "Origin: https://<owner>.github.io"

# 6. Download with no Authorization -> 401 {"error":"sign-in-required",...}
curl -i -X POST "$W/api/download" -H "Origin: https://<owner>.github.io" \
  -H "Content-Type: application/json" -d '{"file_id":123}'

# 7. subtitle-file with an off-host link -> 403 {"error":"bad-link",...}
curl -i "$W/api/subtitle-file?link=https%3A%2F%2Fevil.example%2Fx.srt" \
  -H "Origin: https://<owner>.github.io"

# 8. TMDB route -> 200 with the token set, 404 {"error":"not-found",...} without it;
#    the token never appears in the body either way.
curl -s "$W/api/tmdb/find/tt0041959?external_source=imdb_id" \
  -H "Origin: https://<owner>.github.io" | head -c 200
```

## Limits, honestly

- The per-IP soft cap (60 requests a minute) counts in the Cache API. On a `*.workers.dev`
  hostname Cloudflare makes cache operations no-ops, so there it never limits anything; it only
  works on a custom domain, and even then per data centre. It always fails open. OpenSubtitles'
  own limits (per key, per user) still apply. A real cap needs the Workers Rate Limiting binding.
- Responses expose `Retry-After` and `X-RateLimit-*` (`Access-Control-Expose-Headers`), so Lite
  can say how long to wait after a 429.
- A VIP account's `base_url` from `/login` is not honoured: every call goes to
  `UPSTREAM_BASE`, which serves VIP accounts too.
- Lite works without this Worker: films play and viewers add their own subtitle files; online
  search is the only thing the Worker adds.

## Roll back

```bash
npx wrangler deployments list
npx wrangler rollback [<deployment-id>]
```

Instant, no build. Secrets are not part of a deployment, so a rollback never loses `OS_API_KEY`.
