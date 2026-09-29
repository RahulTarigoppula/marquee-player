import { describe, expect, test } from 'vitest'
import { noPrintReason, type ProbeEnv, probeCapability, sniffPrint } from './capability'

type Answers = Partial<Record<'MP4/H.264' | 'WebM/VP9' | 'AV1' | 'HEVC' | 'AC-3', string>>

const MIME_LABEL: Record<string, keyof Answers> = {
  'video/mp4; codecs="avc1.42E01E, mp4a.40.2"': 'MP4/H.264',
  'video/webm; codecs="vp9, opus"': 'WebM/VP9',
  'video/webm; codecs="av01.0.05M.08"': 'AV1',
  'video/mp4; codecs="hvc1.1.6.L93.B0"': 'HEVC',
  'audio/mp4; codecs="ac-3"': 'AC-3',
}

const env = (answers: Answers, extra: Partial<ProbeEnv> = {}): ProbeEnv => ({
  canPlayType: (mime) => answers[MIME_LABEL[mime] ?? 'AC-3'] ?? '',
  ...extra,
})

const decoder = (supported: Record<string, boolean>) => ({
  isConfigSupported: async (c: { codec: string }) => ({
    supported: supported[c.codec] ?? false,
  }),
})

const CHROME: Answers = { 'MP4/H.264': 'probably', 'WebM/VP9': 'probably', AV1: 'probably' }

describe('capability probe', () => {
  test('marks natively playable codecs with a tick', async () => {
    const cap = await probeCapability(env(CHROME))
    expect(cap.line).toContain('MP4/H.264 ✓')
    expect(cap.line).toContain('WebM/VP9 ✓')
    expect(cap.line).toContain('AV1 ✓')
    expect(cap.codecs[0]).toEqual({ label: 'MP4/H.264', ok: true, via: 'native' })
  })

  test('accepts maybe as native support', async () => {
    const cap = await probeCapability(env({ 'MP4/H.264': 'maybe' }))
    expect(cap.codecs[0]?.via).toBe('native')
  })

  test('marks AV1 with a cross when canPlayType is empty', async () => {
    const cap = await probeCapability(env({ ...CHROME, AV1: '' }))
    expect(cap.line).toContain('AV1 ✗')
  })

  test('falls back to WebCodecs for HEVC', async () => {
    const cap = await probeCapability(
      env(CHROME, { VideoDecoder: decoder({ 'hvc1.1.6.L93.B0': true }) }),
    )
    expect(cap.line).toContain('HEVC ✓ (WebCodecs)')
    expect(cap.codecs.find((c) => c.label === 'HEVC')?.via).toBe('webcodecs')
  })

  test('marks HEVC with a cross when both probes are negative', async () => {
    const cap = await probeCapability(env(CHROME, { VideoDecoder: decoder({}) }))
    expect(cap.line).toContain('HEVC ✗')
    expect(cap.line).not.toContain('WebCodecs unavailable')
  })

  test('marks AC-3 with a cross', async () => {
    const cap = await probeCapability(
      env(CHROME, { VideoDecoder: decoder({}), AudioDecoder: decoder({}) }),
    )
    expect(cap.line).toContain('AC-3 ✗')
  })

  test('always reads MKV partial without probing it', async () => {
    const seen: string[] = []
    const cap = await probeCapability({
      canPlayType: (m) => {
        seen.push(m)
        return 'probably'
      },
    })
    expect(cap.line).toContain('MKV partial')
    expect(seen.some((m) => m.includes('matroska'))).toBe(false)
  })

  test('ends the line with WebCodecs unavailable when VideoDecoder is undefined', async () => {
    const cap = await probeCapability(env(CHROME))
    expect(cap.webCodecsAvailable).toBe(false)
    expect(cap.line.endsWith('· WebCodecs unavailable')).toBe(true)
    expect(cap.line).toBe(
      'MP4/H.264 ✓ · WebM/VP9 ✓ · AV1 ✓ · HEVC ✗ · AC-3 ✗ · MKV partial · WebCodecs unavailable',
    )
  })

  test('treats a throwing isConfigSupported as unsupported', async () => {
    const cap = await probeCapability(
      env({}, { VideoDecoder: { isConfigSupported: () => Promise.reject(new TypeError('x')) } }),
    )
    expect(cap.codecs.every((c) => !c.ok)).toBe(true)
  })
})

const ebml = (body: string) =>
  new Uint8Array([0x1a, 0x45, 0xdf, 0xa3, ...new TextEncoder().encode(body)])

describe('print sniff', () => {
  test('names the exact missing decoder for an MKV with HEVC and AC-3', async () => {
    const cap = await probeCapability(
      env(CHROME, { VideoDecoder: decoder({ 'hvc1.1.6.L93.B0': true }) }),
    )
    const sniff = sniffPrint(ebml('....V_MPEGH/ISO/HEVC....A_AC3....'), 'film.mkv')
    expect(sniff).toEqual({ container: 'MKV', video: 'HEVC', audio: 'AC-3' })
    const why = noPrintReason(sniff, cap)
    expect(why.tags).toBe('MKV · HEVC · AC-3')
    expect(why.sentence).toBe('This browser has no AC-3 decoder.')
  })

  test('names a video decoder before an audio one', async () => {
    const cap = await probeCapability(env(CHROME))
    const sniff = sniffPrint(ebml('V_MPEGH/ISO/HEVC A_DTS'), 'film.mkv')
    expect(noPrintReason(sniff, cap).missing).toBe('HEVC')
  })

  test('says it could not decode when no codec is known to be missing', async () => {
    const cap = await probeCapability(env(CHROME))
    const why = noPrintReason(sniffPrint(new Uint8Array(400), 'mystery.bin'), cap)
    expect(why.missing).toBeNull()
    expect(why.sentence).toBe("This browser couldn't decode this print.")
    expect(why.tags).toBe('BIN')
  })

  test('recognises MP4, WebM, AVI and TS containers', () => {
    const mp4 = new Uint8Array([0, 0, 0, 24, ...new TextEncoder().encode('ftypisom avc1 mp4a')])
    expect(sniffPrint(mp4, 'x.mp4')).toEqual({ container: 'MP4', video: 'H.264', audio: 'AAC' })
    expect(sniffPrint(ebml('V_VP9 A_OPUS'), 'x.webm').container).toBe('WebM')
    const avi = new TextEncoder().encode('RIFF\0\0\0\0AVI LIST')
    expect(sniffPrint(avi, 'x.avi').container).toBe('AVI')
    const ts = new Uint8Array(400)
    ts[0] = 0x47
    ts[188] = 0x47
    expect(sniffPrint(ts, 'x').container).toBe('TS')
    expect(sniffPrint(new Uint8Array(8), 'noext').container).toBeNull()
  })
})
