import { describe, expect, test } from 'vitest'
import download406 from '../../../test/fixtures/os/download-406.json'
import downloadOk from '../../../test/fixtures/os/download-ok.json'
import loginOk from '../../../test/fixtures/os/login-ok.json'
import loginVip from '../../../test/fixtures/os/login-vip.json'
import {
  ANONYMOUS,
  quotaFromDownload,
  quotaFromLogin,
  quotaFromUserInfo,
  SENTENCE_EXHAUSTED,
  SENTENCE_LOW,
  ticketStrip,
} from './tickets'
import type { OsLoginResponse, Quota } from './types'

const NOW = new Date('2026-09-06T15:44:00Z')
const signedIn10: Quota = { ...quotaFromLogin(loginOk as OsLoginResponse), total: 10 }
const withRemaining = (remaining: number, base: Quota = signedIn10) =>
  quotaFromDownload({ ...downloadOk, remaining }, base)

describe('ticket strip', () => {
  test('prints remaining of total and the UTC reset from the download response', () => {
    const strip = ticketStrip(quotaFromDownload(downloadOk, signedIn10), { now: NOW })
    expect(strip).toEqual({
      text: '7 OF 10 TONIGHT · RESETS 00:00 UTC',
      sentence: null,
      ariaLabel: '7 of 10 downloads left tonight',
      state: 'n-left',
      pendingTear: false,
    })
  })

  test('turns crimson with a sign-in or Subdl offer at two left', () => {
    const strip = ticketStrip(withRemaining(2), { now: NOW })
    expect(strip.text).toBe('2 OF 10 TONIGHT · RESETS 00:00 UTC')
    expect(strip.state).toBe('two-left')
    expect(strip.sentence).toBe(SENTENCE_LOW)
    expect(strip.ariaLabel).toBe('2 of 10 downloads left tonight')
  })

  test('reads no tickets left at zero remaining', () => {
    const strip = ticketStrip(withRemaining(0), { now: NOW })
    expect(strip).toMatchObject({
      text: 'NO TICKETS LEFT TONIGHT · RESETS 00:00 UTC',
      sentence: SENTENCE_EXHAUSTED,
      ariaLabel: 'No downloads left tonight',
      state: 'exhausted',
    })
  })

  test('reads no tickets left on an HTTP 406 whatever the counter said', () => {
    const q = quotaFromDownload(download406, signedIn10)
    expect(ticketStrip(q, { now: NOW }).state).toBe('exhausted')
    expect(ticketStrip(withRemaining(7), { now: NOW, status406: true }).state).toBe('exhausted')
  })

  test('reads anonymous when signed out', () => {
    expect(ticketStrip(ANONYMOUS, { now: NOW })).toEqual({
      text: 'ANONYMOUS · 5 PER DAY PER IP',
      sentence: null,
      ariaLabel: 'Anonymous: 5 downloads per day per network',
      state: 'anonymous',
      pendingTear: false,
    })
  })

  test('trusts allowed_downloads from the login response, never a constant', () => {
    const q = quotaFromDownload(downloadOk, quotaFromLogin(loginOk as OsLoginResponse))
    const strip = ticketStrip(q, { now: NOW })
    expect(strip.text.startsWith('7 OF 20 TONIGHT')).toBe(true)
    expect(strip.state).toBe('n-left')
  })

  test('marks a VIP account with its own total', () => {
    const q = quotaFromDownload(downloadOk, quotaFromLogin(loginVip as OsLoginResponse))
    expect(ticketStrip(q, { now: NOW })).toMatchObject({ text: '7 OF 1000 · VIP', state: 'vip' })
  })

  test('shows the count before the tear while the tear animation runs', () => {
    const q = withRemaining(6)
    expect(ticketStrip(q, { now: NOW, pendingTear: true })).toMatchObject({
      text: '7 OF 10 TONIGHT · RESETS 00:00 UTC',
      pendingTear: true,
    })
    expect(ticketStrip(q, { now: NOW }).text).toBe('6 OF 10 TONIGHT · RESETS 00:00 UTC')
  })

  test('refills the strip once the reset time has passed', () => {
    const later = new Date('2026-09-07T00:00:01Z')
    expect(ticketStrip(withRemaining(0), { now: later }).text).toBe('10 OF 10 TONIGHT')
  })

  test('reads unknown when signed in before any download reported a count', () => {
    const q = quotaFromLogin(loginOk as OsLoginResponse)
    expect(ticketStrip(q, { now: NOW })).toMatchObject({
      text: '20 TICKETS A DAY',
      ariaLabel: '20 downloads a day',
      state: 'unknown',
    })
    const bare: Quota = { ...q, total: null }
    expect(ticketStrip(bare, { now: NOW })).toMatchObject({
      text: 'TICKETS A DAY',
      state: 'unknown',
    })
  })

  test('keeps the known count when signing in again', () => {
    const again = quotaFromLogin(loginOk as OsLoginResponse, withRemaining(5))
    expect(again.remaining).toBe(5)
    expect(again.total).toBe(20)
  })

  test('derives the total from requests plus remaining when login never said', () => {
    const q = quotaFromDownload(downloadOk, { ...ANONYMOUS, signedIn: true })
    expect(q.total).toBe(10)
  })

  test('refreshes the quota from the user info without spending a ticket', () => {
    const q = quotaFromUserInfo(
      { data: { remaining_downloads: 9, allowed_downloads: 20, vip: false, level: 'Sub leecher' } },
      ANONYMOUS,
    )
    expect(q).toMatchObject({ signedIn: true, remaining: 9, total: 20, level: 'Sub leecher' })
    expect(quotaFromUserInfo(null, ANONYMOUS)).toBe(ANONYMOUS)
    expect(quotaFromUserInfo({ data: {} }, signedIn10)).toMatchObject({ total: 10, vip: false })
  })
})
