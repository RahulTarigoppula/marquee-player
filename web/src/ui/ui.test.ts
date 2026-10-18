import { getByRole, queryByRole } from '@testing-library/dom'
import { describe, expect, test, vi } from 'vitest'
import { initial, reduce } from '../engine/threading'
import { ANONYMOUS } from '../engine/tickets'
import type { MovieHash } from '../engine/types'
import { booth } from './booth'
import { detentsFor, snapTarget } from './gate'
import { leader } from './leader'
import { liteLanding, skyFor } from './lite'
import { noPrint } from './noPrint'

const REASON = {
  tags: 'MKV · HEVC · AC-3',
  sentence: 'This browser has no AC-3 decoder.',
  missing: 'AC-3',
}
const card = () =>
  noPrint({
    reason: REASON,
    releasesUrl: 'https://github.com/o/marquee/releases/latest',
    onOpenAnother: () => undefined,
  })

describe('No Print card', () => {
  test('never offers the unwired WebCodecs path', () => {
    expect(queryByRole(card(), 'button', { name: 'Try the WebCodecs path' })).toBeNull()
  })

  test('offers exactly the native builds and another film, and names the decoder', () => {
    const el = card()
    getByRole(el, 'link', { name: 'Open in Marquee for Windows / Android' })
    getByRole(el, 'button', { name: 'Open another film' })
    expect(el.querySelectorAll('.noprint__actions > *')).toHaveLength(2)
    expect(el.textContent).toContain('This browser has no AC-3 decoder.')
  })
})

describe('landing', () => {
  const landing = (searchEnabled = true, onFiles = vi.fn()) =>
    liteLanding({
      now: new Date('2026-09-06T21:14:00+05:30'),
      releasesUrl: 'https://github.com/o/marquee/releases/latest',
      searchEnabled,
      language: 'en',
      onFiles,
      onOffice: () => undefined,
      onLanguage: () => undefined,
      strip: document.createElement('div'),
    })

  test('opens the real file input from the keyboard on Enter and Space', () => {
    const view = landing()
    const click = vi.spyOn(view.input, 'click').mockImplementation(() => undefined)
    const doors = getByRole(view.el, 'button', { name: /Drop a film here/ })
    expect(doors.tabIndex).toBe(0)
    doors.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))
    doors.dispatchEvent(new KeyboardEvent('keydown', { key: ' ', bubbles: true }))
    expect(click).toHaveBeenCalledTimes(2)
    expect(view.input.type).toBe('file')
    expect(view.input.multiple).toBe(true)
    expect(view.input.accept).toContain('.vtt')
  })

  test('without a server, offers no ticket office and points to the apps for search', () => {
    const view = landing(false)
    expect(queryByRole(view.el, 'button', { name: /Ticket office/ })).toBeNull()
    expect(view.el.textContent).toContain('Online subtitle search needs the')
    expect(getByRole(view.el, 'link', { name: 'Windows / Android app' }).getAttribute('href')).toBe(
      'https://github.com/o/marquee/releases/latest',
    )
    expect(view.el.textContent).toContain('nothing is uploaded')
  })

  test('with a server, says what a search sends', () => {
    const view = landing(true)
    getByRole(view.el, 'button', { name: /Ticket office/ })
    expect(view.el.textContent).toContain('the title and year from its file name')
  })

  test('picks the sky band from the local clock', () => {
    expect(skyFor(new Date('2026-09-06T21:14:00+05:30'))).toBe('night')
    expect(skyFor(new Date('2026-09-06T06:00:00+05:30'))).toBe('dawn')
    expect(skyFor(new Date('2026-09-06T12:00:00+05:30'))).toBe('day')
    expect(skyFor(new Date('2026-09-06T18:00:00+05:30'))).toBe('dusk')
  })
})

describe('leader', () => {
  test('announces each phase once, never per sweep frame', () => {
    const view = leader(
      {
        onChoose: () => undefined,
        onPick: () => undefined,
        onManual: () => undefined,
        onSidecar: () => undefined,
      },
      document.createElement('div'),
    )
    const live = view.el.querySelector('[aria-live="polite"]') as HTMLElement
    const seen: string[] = []
    new MutationObserver(() => seen.push(live.textContent ?? '')).observe(live, {
      childList: true,
      characterData: true,
      subtree: true,
    })
    let m = initial({ subdlEnabled: false, language: 'en' }, ANONYMOUS)
    const events = [
      { type: 'open', at: 0, parsed: null, quota: ANONYMOUS },
      { type: 'tick', at: 100 },
      { type: 'tick', at: 200 },
      { type: 'hashed', at: 300, hash: '0000000000020000' as MovieHash },
      { type: 'tick', at: 400 },
      { type: 'failed', at: 500, failure: 'offline' },
    ] as const
    return (async () => {
      for (const e of events) {
        m = reduce(m, e).machine
        view.render(m, null)
        await Promise.resolve()
      }
      expect(seen).toEqual(['Reading the print', 'Searching subtitles'])
      const dial = view.el.querySelector('.leader') as HTMLElement
      expect(dial.classList.contains('is-stalled')).toBe(true)
      expect(
        getByRole(view.el, 'group', { name: 'What next', hidden: true }).textContent,
      ).toContain('Play without subtitles')
    })()
  })
})

describe('booth sync rule', () => {
  test('moves the ruler under a fixed caret and announces plus seconds', () => {
    const view = booth({
      onTrack: () => undefined,
      onSize: () => undefined,
      onSync: () => undefined,
      onFindAnother: () => undefined,
      onPick: () => undefined,
      onClose: () => undefined,
    })
    const caret = view.el.querySelector('.rule__caret') as HTMLElement
    const before = caret.getAttribute('style')
    view.setSync(0.35)
    const ruler = view.el.querySelector('.rule__ticks') as HTMLElement
    expect(ruler.style.getPropertyValue('--rx')).toBe('-70px')
    expect(caret.getAttribute('style')).toBe(before)
    expect(getByRole(view.el, 'slider', { hidden: true }).getAttribute('aria-valuetext')).toBe(
      'plus 0.35 seconds',
    )
  })
})

describe('film gate detents', () => {
  const chapters = [0, 1800, 4200, 7200]
  test('snaps a release within 6 px to the detent', () => {
    expect(snapTarget(152, 800, 9663, chapters)).toBe(1800)
  })
  test('seeks freely when the nearest detent is further than 6 px', () => {
    expect(snapTarget(160, 800, 9663, chapters)).toBeCloseTo(1932.6, 1)
    expect(snapTarget(800, 800, 9663, chapters)).toBe(9663)
    expect(snapTarget(0, 800, 9663, chapters)).toBe(0)
  })
  test('places a detent every five minutes when there are no chapters', () => {
    expect(detentsFor(900)).toEqual([0, 300, 600, 900])
  })
})
