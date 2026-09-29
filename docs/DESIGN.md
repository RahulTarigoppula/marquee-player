# Marquee — DESIGN.md (design system, v1)

**Project:** 08 · The No-Hassle Smart Media Player (codename "Marquee") · **Date:** 2026-09-06
**Binding docs:** `_shared/DECISIONS.md` (D1 Marquee exception: Flutter + media_kit native, Vite + TS web; D2 Worker; D5 licensing; D7 token contract), `docs/RESEARCH.md` (stack, moviehash pipeline, quota, libass, CI), `_shared/research/DESIGN-TOOLKIT.md` (fonts/libs).
**Rule of the house:** `design/preview.html` is the visual contract (D9.3). If the real app looks worse than the preview, it is not done.
**Portfolio typography lane:** cinema marquee / title-card — Big Shoulders Display for display, Geist for UI. Fraunces and Bebas Neue are forbidden here (Fraunces belongs to Napkin's editorial lane).

---

## 1. Identity

**Name:** HOUSE LIGHTS (the design system); the app stays *Marquee*.

**One-liner:** *A single-screen cinema at night that dims for you.* Drop a film and the house lights go down, the projector beam finds the screen, an academy leader counts 3-2-1 while the file is hashed and its subtitles are threaded, and the walls glow with the colour of whatever is playing. Every UI state is a lighting state; chrome is replaced by light.

**Three adjectives:** Dim · Warm · Honest.

**What it must never look like**
- **Retro-cinema kitsch.** No popcorn, curtains, red-velvet gradients, art-deco fonts, fake scratches, chasing bulbs. Crimson is a 1 px trim line and a ticket stub, nothing more. Grain lives in the lobby at 4 % and never touches the picture.
- **"YouTube ambient mode in a dark player."** Plex, VLC and Kodi are a black rectangle with a progress bar. Marquee is a *room*: a beam, walls that receive light, a sky that knows the time, a working academy leader as the loading indicator, and a film gate as the seek bar. If a screenshot could be mistaken for any of those three, it has drifted.
- **Napkin's paper.** No cream page ground in playback, no hairline tables, no folio numerals as ornament, no serif anywhere. Our type is condensed caps and a quiet grotesk on near-black.
- **Skeuomorphic hardware.** No bevels, gloss, brass knobs or wood. Controls are small luminous marks (Teenage-Engineering-style glyphs), not rendered objects. Light is functional, never decorative: if an element glows, it is *on*.
- **Loud.** More than one accent per screen, a red error banner over the picture, a spinner. Errors are a stalled leader numeral and a plain sentence.

---

## 2. Moodboard & references

| Reference | What we take | URL |
|---|---|---|
| Edward Hopper, *New York Movie* (1939) | The exact value structure: a pool of amber sconce light beside a near-black auditorium | https://www.moma.org/collection/works/79616 |
| SMPTE / Academy universal leader | The rotating radial-wipe countdown and the 2-pop, repurposed as the *real* progress indicator | https://en.wikipedia.org/wiki/Film_leader |
| *Cinema Paradiso* projection booth | Dust hanging in the beam, the motor whir — the lobby room tone and the OGL beam shader | https://www.criterion.com/films/28763-cinema-paradiso |
| Apple TV aerial screensavers | A place whose sky shifts with the local clock | https://support.apple.com/en-us/102290 |
| Chicago Theatre / Hollywood Theatre marquees at 2 a.m. | Small tungsten bulbs, condensed letters, warm halation, no chase animation | https://commons.wikimedia.org/wiki/Category:Chicago_Theatre |
| Roger Deakins, *Blade Runner 2049* (Wallace HQ) | A single cone of light as the only architecture in a black room | https://www.rogerdeakins.com/ |
| *Monument Valley* (ustwo) | Depth from a few flat planes and one light source, never texture | https://www.monumentvalleygame.com/ |
| Teenage Engineering OP-1 glyph language | Controls drawn as small functional luminous marks, not buttons | https://teenage.engineering/products/op-1 |
| Criterion Collection disc menus | Stillness, a single frame, typography that respects the film | https://www.criterion.com/ |
| The exit sign | The one green light allowed in a dark cinema — used only for "synced" and "saved" | https://en.wikipedia.org/wiki/Exit_sign |
| Big Shoulders (Patric King, Chicago sign painting) | The marquee letterform — bulbs on a sign without a novelty glyph | https://github.com/xotypeco/big_shoulders |
| Cinema tickets, perforated strips (grafted from The Booth) | Download quota as tickets you tear | https://commons.wikimedia.org/wiki/Category:Cinema_tickets |
| Slide rules (grafted from concept 1's "slide rule") | Subtitle delay as a mono ruler sliding under a fixed caret | https://commons.wikimedia.org/wiki/Category:Slide_rules |

---

## 3. Judging summary

Scores 1–10; total /50. Judged harshly on genericness *and* on illegible art-direction. Portfolio overlap counts against distinctiveness.

| Concept | Distinct. | Vibe fit | Usability | Feasibility | Screenshot | **Total** | Verdict |
|---|---|---|---|---|---|---|---|
| 1 · House Lights (editorial / paper programme) | 6 | 6 | 8 | 9 | 6 | **35** | Beautiful and cheap, but it is Napkin (03) with a video in it — warm paper, hairlines, folio numerals, one red, stamps — so it fails the "eight apps must look completely different" rule; it also relies on the forbidden Fraunces, and word-only controls ("PAUSE", "−10") are slow to hit in the dark. Grafted, not chosen. |
| 2 · House Lights (atmospheric / the room) | 9 | 10 | 7 | 6 | 10 | **42** | **Winner.** The only concept whose signature *is* the app's real state machine (house up / dimmed / dark; the leader is the real promise chain). Nails "seamless and cinematic". Costs: a shader, bias-light sampling and a body font outside the portfolio lane — all fixed below. |
| 3 · The Booth (tactile projectionist's console) | 9 | 7 | 5 | 4 | 9 | **34** | The most fun to touch, but the reel-as-seek and drag-to-open drawer have no discoverability, the four-typeface material system is heavy, scrub thumbnails need a second background player, and modern skeuomorphism is one gloss highlight away from 2010. Not "modern intuitive UI". |

**Why the room won.** The brief asks for VLC power in a modern, intuitive UI that is also screenshot-worthy. Concept 2 keeps every standard affordance (tap to reveal controls, a horizontal seek bar, bottom sheets, a normal settings page) and *re-lights* them instead of replacing them, so nothing has to be unlearned. Its distinctive elements — beam, leader, film gate, bias-lit walls, marquee — are all functional. It maps directly onto the verified stack (RESEARCH §2, §5.3, §7): media_kit screenshots for bias light, Impeller fragment shaders on Windows + Android, `requestVideoFrameCallback` on the web.

**What was grafted (and how conflicts were resolved)**
1. **The Folio** (from concept 1). One persistent line, top-left, in Geist Mono: `REEL 01 · 01:12:44 · −01:28:19`. It is the frameless window's title bar on Windows and the only chrome that survives auto-hide (at 40 % opacity). *Conflict:* concept 1 set it in a serif on paper — here it is mono caps on the wall, lit by the beam.
2. **The Sync Rule** (concept 1's "slide rule", replacing concept 2's brass knob). Subtitle delay is a horizontal mono ruler (−2.00 … +2.00 s) sliding under a fixed tungsten caret with 50 ms detents. *Conflict:* knobs are hardware; a rule is a lit mark. Per-file offsets remembered by moviehash.
3. **Tear a ticket** (from The Booth). The OpenSubtitles quota is a perforated strip; each download tears one with a paper-rip and a medium haptic; at 2 left the strip turns crimson and offers "sign in at the ticket office" or the Subdl slot. *Conflict:* the crimson budget — the strip is the *one* crimson element on the Threading screen; the marquee trim is hidden there.
4. **Chapter detents + the first-run nudge** (from The Booth). The film-gate seek snaps at chapters (or every 5 min) with a selection tick, and on first run the gate slides 12 px and back to show it can be dragged. *Conflict:* none; The Booth's friction/coast physics are dropped — the gate uses the one spring.

Fonts swapped for the portfolio rule: Instrument Sans → **Geist**; JetBrains Mono → **Geist Mono** (one designer family, tabular figures, `ss01` for a slashed zero in hashes). Big Shoulders Display is in the reserved lane and stays.

---

## 4. Colour system

Two rooms, two palettes. **Auditorium (dark) is the default and the only palette for playback** — a light theme over a moving picture is a contradiction (glare, halation, subtitle contrast), so dark-only for the Auditorium is the D7 justification. **Matinee (light)** exists for the Lobby, Subtitle Booth and Ticket Office only, follows `prefers-color-scheme` or the user's pin, and is never applied while a file is open.

### 4.1 Auditorium (default, `:root`)

Contrast ratios computed against `--bg` / `--surface` / `--surface-2` (WCAG 2.x relative luminance).

| Token | Hex | Usage | Contrast |
|---|---|---|---|
| `--bg` | `#07060A` | Auditorium black — page ground and the wall behind the picture. Warm-violet black; only the letterbox behind the video itself is `#000` | — |
| `--bg-elevated` | `#120E15` | Booth — sheets, dialogs, lobby floor | — |
| `--surface` | `#1B1620` | Velvet — cards, poster rail, subtitle candidate rows | — |
| `--surface-2` | `#26202B` | Velvet lit — hover/pressed surfaces, seek-strip base, film-gate track | — |
| `--ink` | `#F3E9DA` | Screen white — primary text, marquee letters, timecodes | 16.8 : 1 on bg · 14.8 on surface · 13.2 on surface-2 |
| `--ink-muted` | `#A89C8C` | Secondary: release names, fps, meta | 7.5 · 6.6 · 5.9 |
| `--ink-faint` | `#8C8276` | Tertiary: labels, tick numerals, placeholder. **Never body text on `--surface-2`** (4.2) — use ≥ 18 px there | 5.4 · 4.7 · 4.2 |
| `--accent` | `#FFC56E` | Tungsten bulb — marquee bulbs, aisle lights, active controls, the beam colour, primary action fill | 13.0 on bg · 13.5 on #000 |
| `--accent-ink` | `#1A1006` | Text on tungsten (filled buttons, Open disc) | 12.0 on accent |
| `--accent-2` | `#A3252F` | Curtain crimson — marquee trim line (1 px), the ticket stub, low-quota strip. **Non-text only** (2.8 on bg); when crimson must carry text use `--accent-2-lit` | 2.8 (decorative) |
| `--accent-2-lit` | `#E0525C` | Crimson brightened for text/glyphs on dark ("2 tickets left") | 5.3 · 4.7 · 4.2 (≥ 18 px on surface-2) |
| `--success` | `#5FD48A` | Exit-sign green — MATCH bulb, "attached", "saved beside file" | 10.8 · 9.5 · 8.5 |
| `--warning` | `#F5A05F` | Sodium orange — quota nearly out, link expiring, hwdec fallback | 9.7 · 8.5 · 7.6 |
| `--danger` | `#E5484D` | Undecodable print, 429/406, expired link | 5.2 · 4.5 · 4.1 (≥ 18 px on surface-2); ink on danger fill is 3.3 → use `--accent-ink` on danger fills |
| `--border` | `#2A2330` | 1 px seams: sheet top edge, rail dividers | decorative |
| `--border-strong` | `#3D3446` | Pressed/active seams, input underlines | decorative (interactive outlines use `--ink-faint`) |
| `--focus` | `#FFD68A` | Keyboard focus ring, 2 px outer + 2 px offset; also the bias-light fallback tint before the first sample | 14.7 on bg |

### 4.2 Matinee (`[data-theme="matinee"]`, Lobby / Booth / Ticket Office only)

| Token | Hex | Usage | Contrast |
|---|---|---|---|
| `--bg` | `#F1E8D8` | Cream lobby wall (daylight through the doors) | — |
| `--bg-elevated` | `#F8F2E6` | Sheets | — |
| `--surface` | `#E8DECB` | Cards, rows | — |
| `--surface-2` | `#DDD1BC` | Hover/pressed | — |
| `--ink` | `#2A2226` | Primary text | 12.8 · 11.6 · 10.3 |
| `--ink-muted` | `#5E5350` | Secondary | 6.1 · 5.6 · 4.9 |
| `--ink-faint` | `#605651` | Tertiary | 5.9 · 5.3 · 4.7 |
| `--accent` | `#7F4800` | Dark tungsten — text/icon accent, filled buttons | 6.1 · 5.6 · 4.9 |
| `--accent-ink` | `#FFF6E6` | Text on accent | 6.9 on accent |
| `--accent-2` | `#A3252F` | Crimson trim + ticket (carries text in Matinee) | 6.0 · 5.5 · 4.9 |
| `--accent-2-lit` | `#A3252F` | same as accent-2 in light | — |
| `--success` | `#186639` | Exit green, darkened | 5.8 · 5.3 · 4.6 |
| `--warning` | `#8A4B00` | | 5.6 · 5.1 · 4.5 |
| `--danger` | `#A8231C` | | 5.9 · 5.4 · 4.8 |
| `--border` | `#D6CAB5` | | decorative |
| `--border-strong` | `#B9AB93` | | decorative |
| `--focus` | `#7A4A00` | | 6.2 on bg |

**Matinee carries two ink tiers, not three — on purpose.** `--ink-muted` (6.11 · 5.56 · 4.92 on `--bg` · `--surface` · `--surface-2`) and `--ink-faint` (5.86 · 5.34 · 4.72) are only ~4 % apart, so the three-tier hierarchy that the Auditorium carries by lightness (16.8 / 7.5 / 5.4) reads as two tiers here. That is a constraint of the cream ground, not an oversight: any `--ink-faint` light enough to be a visibly third tier falls under AA — `#7A6E68`, the obvious candidate, measures **4.06 · 3.70 · 3.27**, and DECISIONS D7 makes 4.5 : 1 non-negotiable for text. **So in Matinee the third tier is expressed by size and letter-spacing, never by lightness:** labels, tick numerals and placeholders drop to `--text-xs` with the mono face and +0.06em tracking while staying on `--ink-faint`. Do not “fix” the palette by lightening the token; the TESTING §2.12 Matinee rows assert these exact ratios.

The marquee bulbs are **off** in Matinee (letters are painted `--ink`, the box is `--surface-2`); the beam and dust are not drawn; the sky band is at full strength (it is daylight). Opening a file always switches to Auditorium via HOUSE-DOWN.

### 4.3 Semantic & derived tokens

| Token | Value | Notes |
|---|---|---|
| `--picture-bg` | `#000000` | Only ever behind the `<video>`/texture. Never a page ground |
| `--wall-glow` | runtime | 5-stop radial gradient from bias-light sampling; falls back to `--focus` at 6 % alpha |
| `--bulb-halo` | `0 0 6px 1px color-mix(in oklch, var(--accent) 55%, transparent)` | The only glow allowed; applied to lit bulbs/aisle lights only |
| `--booth-glass` | `color-mix(in oklch, var(--bg-elevated) 78%, transparent)` + `backdrop-filter: blur(24px)` | Sheets over the paused frame |
| `--sky-dawn / --sky-day / --sky-dusk / --sky-night` | `#3A2A2E → #2A2E3A → #2F2438 → #0B0A10` | Lobby sky band, mixed at 6 % saturation in Auditorium; full strength in Matinee (`#F5C9A8 / #C9D6E8 / #C8A9D6 / #1A1622`) |
| `--grain-opacity` | `0.04` | Lobby and sheets only; `0` in the Auditorium |

**Gradients, materials, textures**
- Exactly one gradient family: the **sky band** (linear, 4 stops, ±6 % saturation) and the **wall glow** (radial, from the sampled frame). No gradient buttons, no gradient text, no crimson gradients.
- **Beam**: a soft cone (fragment shader) in `--accent` at 8–14 % alpha with 3-octave value noise and 200 dust sprites; DPR capped at 1.5 desktop / 1.0 Android; static radial-gradient fallback.
- **Booth glass**: `--booth-glass` + 1 px `--border` top edge. Never over the picture while it plays (only over a paused frame).
- **Grain**: SVG `feTurbulence` (web) / a 256 px tiled noise PNG or fragment shader (Flutter) at `--grain-opacity`; disabled on the picture and in reduced motion.
- **Bulbs**: 5 px circles of `--accent` with `--bulb-halo`; off state is `--surface-2` with a 1 px `--border-strong` ring.

---

## 5. Typography

| Role | Family | Source | Weights / axes | Where |
|---|---|---|---|---|
| `--font-display` | **Big Shoulders Display** | Google Fonts https://fonts.google.com/specimen/Big+Shoulders+Display · Fontsource `@fontsource-variable/big-shoulders-display` (OFL 1.1) | variable wght; use 500 / 700 / 900 | Marquee title, leader numerals, big timecode, section heads in caps |
| `--font-body` | **Geist** | https://fonts.google.com/specimen/Geist · `@fontsource-variable/geist` · TTFs from https://github.com/vercel/geist-font (OFL 1.1) | variable wght; 400 / 500 / 600 | All UI copy, body, buttons, settings |
| `--font-mono` | **Geist Mono** | https://fonts.google.com/specimen/Geist+Mono · `@fontsource-variable/geist-mono` (OFL 1.1) | 400 / 500; `font-variant-numeric: tabular-nums`; `ss01` slashed zero for hashes | Folio, timecodes, moviehash, fps, sub-delay, quota, keyboard cue sheet |
| Subtitles | **Noto Sans** | bundled `assets/fonts/NotoSans-Regular.ttf` (OFL) for libass `libassAndroidFont`; JASSUB default on web | 400 / 700 | Rendered by libass/JASSUB only — never the brand fonts on the picture |

**Rationale.** Big Shoulders is drawn from Chicago sign painting, so the wordmark and every film title read as bulbs on a sign without a novelty glyph; condensed, a 40-character release title fits one marquee line on a phone. Geist is quiet, slightly warm and never reads as SaaS; Geist Mono shares its skeleton so mono readouts sit inside Geist paragraphs without a jump. Three OFL families, self-hosted via Fontsource on the web and bundled TTFs in Flutter (`FontVariation('wght', 700)` for the marquee).

**On the one overlap with the rest of the portfolio.** Geist is also 01-nocturne's `--font-body`, and it is the only repeat across the eight apps — every display face is distinct (Bricolage Grotesque · Yatra One · Caveat · Righteous · Bodoni Moda · Fraunces · Instrument Serif · Big Shoulders Display) and Fraunces stays reserved to Chez Fridge. The overlap is deliberate and harmless: the display face is what carries a brand, and the two never read alike — Nocturne pairs Geist with Bricolage on paper-light grounds, Marquee pairs it with condensed Big Shoulders on near-black, in tungsten. If a screenshot of Marquee could be mistaken for Nocturne, the problem is the palette and the room, not the body face.

**Type scale** (base 16 px; `clamp()` on the two largest steps)

| Token | rem | px | Face / use |
|---|---|---|---|
| `--text-xs` | 0.75 | 12 | Mono meta, tick numerals (never below this) |
| `--text-sm` | 0.875 | 14 | Secondary UI, candidate meta |
| `--text-base` | 1 | 16 | Body, buttons, list rows |
| `--text-lg` | 1.125 | 18 | Sheet titles, folio on desktop |
| `--text-xl` | 1.375 | 22 | Card titles, big mono readouts |
| `--text-2xl` | 1.75 | 28 | Section heads (display, caps, +0.06 em) |
| `--text-3xl` | 2.25 | 36 | Marquee on phone |
| `--text-4xl` | `clamp(3rem, 6vw, 4rem)` | 48–64 | Marquee on desktop, leader numerals on phone |
| `--text-5xl` | `clamp(5rem, 14vw, 9rem)` | 80–144 | Leader numerals on desktop, "MARQUEE" idle sign |

`--leading-tight: 1.05` (display), `--leading-body: 1.5`.

**Letter-spacing rules.** Display caps: `+0.06em` at ≤ 2xl, `+0.02em` at 3xl and above (condensed faces close up as they grow). Geist body: `0`; Geist small labels (`text-transform: uppercase; font-size: --text-xs; letter-spacing: 0.08em; font-weight: 500`) for section labels. Mono: `0`, `tabular-nums` always on, so timecodes, hashes and delay values never jitter.

**Numerals.** Lining tabular everywhere — there are no oldstyle figures in this app; cinema signage never used them. Big Shoulders numerals in the leader use `font-variant-numeric: tabular-nums` and are centred optically 2 % above geometric centre.

**Scripts.** Subtitles may be any script; libass falls back through Noto Sans only (`sub-font-provider=none` on Android means *only* bundled fonts are available — ship `NotoSans-Regular.ttf` plus, optionally, `NotoSansDevanagari-Regular.ttf` and `NotoSansTamil-Regular.ttf` as an "Indic subtitles" download in the Ticket Office). The UI never displays user subtitle text, so Geist's Latin coverage is fine; language names in the candidate list use ISO codes in mono (`EN · HI · TA`) plus the English exonym in Geist.

---

## 6. Spacing, radius, elevation, borders

| Token | Value | Notes |
|---|---|---|
| `--space-1 … --space-12` | 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64 · 80 · 96 px | 8-pt grid with a 4 px half-step |
| `--radius-sm` | 4 px | Bulb boxes, tickets, chips |
| `--radius-md` | 8 px | Cards, candidate rows, inputs |
| `--radius-lg` | 12 px | Sheets (top corners), posters |
| `--radius-xl` | 20 px | The picture's bezel in the Lobby preview only |
| `--radius-full` | 9999 px | The tungsten Open disc and bulbs — nothing else is a pill |
| `--shadow-1` | `inset 0 1px 0 rgba(255,255,255,.04), 0 2px 6px rgba(0,0,0,.5)` | Rows, chips |
| `--shadow-2` | `inset 0 1px 0 rgba(255,255,255,.05), 0 8px 24px rgba(0,0,0,.55)` | Cards, popovers |
| `--shadow-3` | `inset 0 1px 0 rgba(255,255,255,.06), 0 24px 56px rgba(0,0,0,.65)` | Sheets |
| `--border` / `--border-strong` | 1 px | Seams only; no element has a border on all four sides except the focus ring; inputs are underline-only |
| Layout | phone 20 px margins, 4 columns; desktop max 1280, 12 columns, 24 px gutters | Video is always centred and never overlapped by chrome |
| Touch targets | ≥ 44 × 44 px; the film gate is 56 px tall on phone | |

**One light source.** Every shadow falls *down* (the projector is above and behind the viewer) and every glow is tungsten. Matinee flips the shadow alphas to 0.12 / 0.16 / 0.22.

---

## 7. Motion language

**Principle: motion is lighting, not movement.** Things dim, warm, sweep and settle; they do not bounce or slide across the screen. Translate is ≤ 8 px except for sheets (which rise on the one spring). Type never scales.

| Token | Value | Use |
|---|---|---|
| `--dur-fast` | 120 ms | Bulb/hover states, controls returning on touch |
| `--dur-base` | 240 ms | Control reveal/hide, row selection, sheet content |
| `--dur-slow` | 480 ms | View changes (Lobby ↔ Auditorium View Transition), control fade-out |
| `--dur-house` | 900 ms | Any change of lighting state (house up / dimmed / dark) — Marquee-specific |
| `--ease-out` | `cubic-bezier(0.22, 1, 0.36, 1)` | Everything entering |
| `--ease-in-out` | `cubic-bezier(0.65, 0, 0.35, 1)` | Crossfades, sky |
| `--ease-house` | `cubic-bezier(0.7, 0, 0.3, 1)` | The dimmer curve — slow at both ends |
| `--ease-spring` | `linear(0, 0.006, 0.025 2.8%, 0.101 6.1%, 0.539 18.9%, 0.721 25.3%, 0.849 31.5%, 0.937 38.1%, 0.968 41.8%, 0.991 45.7%, 1.006 50.1%, 1.012 55.4%, 1.011 62.6%, 1.006 71.7%, 1)` | CSS approximation of the one spring |
| Spring (JS / Flutter) | stiffness 380, damping 32, mass 1 | Film-gate thumb, edge dimmers, sheet rise (Motion `spring()` / Flutter `SpringSimulation`) |

**Named animations**

| # | Name | Property | From → To | Duration / easing | Stagger / notes |
|---|---|---|---|---|---|
| 1 | `house-down` | `--house` (0–1) driving wall luminance, sky opacity, bulb intensity, beam cone width | house 1 → 0; sky 1 → 0; bulbs 1 → 0.08 ("embers"); beam 12° → 38° | 900 ms `--ease-house` | Single custom property tweened with `@property`; Flutter: one `AnimationController` feeding a `ColorTween` + shader uniforms |
| 2 | `house-up` | same, reversed | 0 → 1 | 900 ms `--ease-house` | Fires on leaving the Auditorium; the video fades out in the first 300 ms |
| 3 | `bulb-warmup` | `opacity` + `--bulb-halo` alpha per letter | 0 → 1.1 → 1.0 | 320 ms `--ease-out`, overshoot to 110 % for 2 frames | 60 ms per letter, left → right, capped at 24 letters (1.44 s) |
| 4 | `leader-sweep` | conic-gradient mask angle | 0° → 360° | 1000 ms linear per numeral, then a 66 ms black flash | Driven by the real promise chain; a rejected promise stalls the sweep at its current angle |
| 5 | `aisle-reveal` / `aisle-hide` | `opacity` + `translateY` | 0/8 px → 1/0 · 1/0 → 0/8 px | 120 ms `--ease-out` · 480 ms `--ease-in-out` after 2400 ms idle | Folio stays at 40 % opacity |
| 6 | `booth-rise` | `translateY` | 100 % → 0 (sheet); content `opacity` 0 → 1 | spring 380/32 (~420 ms); content 240 ms `--ease-out` delayed 120 ms | Drag-dismiss follows the finger 1:1, snaps on velocity > 300 px/s |
| 7 | `bias-lerp` | 5 gradient colour stops | previous sample → new sample | 600 ms linear (1200 ms in reduced motion) | Sampled every 500 ms desktop / 1000 ms Android |
| 8 | `beam-sway` + `dust-drift` | shader uniforms `angle`, `time` | ±1.5° sine over 9 s; 0.3 px/frame drift | continuous, 30 fps, paused on `visibilitychange` and during playback | Reduced motion: static beam, no dust |
| 9 | `ticket-tear` | `clip-path` on the last ticket + `translateY/rotate` | attached → torn (−12 px, −6°), opacity 1 → 0 | 240 ms `--ease-out` | Medium haptic; strip count decrements after the tear |
| 10 | `gate-snap` | film-gate thumb `x` | release position → nearest chapter/frame | spring 380/32 | Light haptic tick on landing |
| 11 | `sync-rule-snap` | ruler `translateX` | drag position → nearest 50 ms detent | 120 ms `--ease-out` | Selection haptic per detent |
| 12 | `match-bulb` | exit-sign bulb `opacity` + halo | 0 → 1 | 240 ms `--ease-out` after the 2-pop | Fires only when `moviehash_match === true` |

**Reduced motion (`prefers-reduced-motion: reduce` / `MediaQuery.disableAnimations`).** Beam static at idle width, no dust, no parallax, no sky drift; bulbs and leader become 240 ms opacity crossfades (the leader still shows the numeral and stalls honestly); sheets use 200 ms opacity + 8 px translate; bias light still allowed (it is colour, not motion) but lerped over 1200 ms; house-down becomes a 240 ms crossfade; auto-hide still works (it is a fade).

---

## 8. Signature interactions

### 8.1 House lights down
1. A file is dropped (or picked, or tapped in the rail). The Lobby does not navigate yet.
2. `--house` tweens 1 → 0 over 900 ms on the dimmer curve: the sky goes to black, the marquee bulbs fade to embers, wall luminance drops to 4 %, room tone ducks −12 dB.
3. At 300 ms the beam swings from its idle 12° cone to fill the screen area (shader uniform, same curve).
4. At 600 ms the View Transition starts (`document.startViewTransition` / Flutter `Hero` on the picture element): the tapped card's poster grows into the letterboxed picture position over 480 ms `--ease-out`.
5. The Threading leader begins on top of the dark room (8.2). Leaving the player reverses everything (`house-up`).
- **Sound:** a 900 ms sine sweep 200 → 60 Hz at −24 dB synthesised in Web Audio / `flutter_soloud` — no asset. **Haptic:** none (the room is the feedback).
- **Why it delights:** the app visibly *makes room* for the film. It is the gif everyone posts, and it costs one custom property.

### 8.2 The leader (identification staged as the academy countdown)
1. **"3" sweeps** (1000 ms, linear) while the 128 KiB moviehash is read (`osHash` / `openSubtitlesHash`); the 16-hex hash prints beneath in Geist Mono as it resolves (`8e245d9679d31e12`), then file size and container fps.
2. **"2" sweeps** while `GET /subtitles?moviehash=…` runs through the Worker (web) or directly (native). On a hit with `attributes.moviehash_match === true`: a 33 ms 1 kHz **2-pop** at −18 dB, the exit-sign **MATCH** bulb lights green, medium haptic. Filename fallback: the bulb stays dark and the row reads `BY NAME · CHECK SYNC` in `--warning`.
3. **"1" sweeps** while `POST /download` fetches the `.srt` and writes it beside the file (`<video>.<lang>.srt`); a ticket tears off the strip (8.5).
4. **66 ms black flash**, then the first frame; controls are shown once for 2400 ms.
5. Any failure stalls the sweep on its numeral — no fake progress. The fallback list (filename search → Subdl → manual pick → "Skip subtitles") slides in beneath the numeral as rows without leaving the leader. 429/406 stops "2" and the ticket strip explains the quota in one sentence.
- **Physics:** the sweep is a conic-gradient mask; each numeral is a promise, so a fast hit finishes in ~1.2 s total and a slow network shows exactly where it is waiting.
- **Why it delights:** the loading indicator is *true*, and it is the most cinematic object in film history.

### 8.3 Film gate seek with chapter detents
1. The seek bar is a 56 px strip of 35 mm film (sprocket holes are 3 × 4 px `--surface-2` rectangles on `--bg-elevated`); the buffered range is a lighter strip; the playhead is **the frame in the gate** — a lit 16:9 window with a 1 px `--accent` edge.
2. Dragging pulls a thumbnail through the gate (web: hidden cloned `<video>` + canvas; native: a cached JPEG strip built by a second muted `hwdec=no` player after open, or a timecode-only gate if it stalls). The folio shows the target timecode live.
3. Detents at chapters (mpv `chapter-list`) or every 5 min: passing one gives a selection tick and the gate edge flashes to 100 % for one frame.
4. Release snaps to the nearest frame with the 380/32 spring and a light haptic. Dragging *up* off the strip switches to **FINE** (1/8 speed; label appears in mono) — VLC precision without a second control.
5. First run: the gate slides 12 px right and back once (`--dur-base`) with the hint "drag the gate".
- **Why it delights:** the seek bar looks like the medium; the detents make chapters *felt*.

### 8.4 The sync rule (subtitle delay)
1. Beside the gate sits a small mono readout `SYNC +0.00`. Tap (or press `J`/`K`) and a ruler appears above the controls: mono numerals `−2.00 … +2.00`, a tick every 50 ms, sliding horizontally under a fixed tungsten caret.
2. Drag the ruler; it snaps to 50 ms detents (`sync-rule-snap`) with a selection haptic; `J`/`K` step 50 ms, `Shift` steps 500 ms. The value is written live to mpv `sub-delay` / the VTT cue offset and printed in the folio: `SUB +0.35`.
3. The offset is remembered per moviehash and shown as a small `±` beside the title in the Lobby rail.
4. Reset is a long-press on the readout (or `Shift+J+K`) — the ruler glides home with the spring.
- **Why it delights:** the value is legible at arm's length, the detents are audible, and exact numbers build trust — no brass to squint at.

### 8.5 Marquee warm-up and the ticket strip
1. When identification returns `feature_details` (title, year, S/E), the film's title is spelled onto the lobby marquee letter by letter (`bulb-warmup`, 60 ms stagger). It stays lit as **NOW SHOWING** until another film replaces it. At local night the bulbs carry a 0.5 % random flicker; by day they are off and the letters are simply painted.
2. Each subtitle download tears one ticket from the perforated strip in the Threading screen and Ticket Office (`ticket-tear`, medium haptic, a short paper-rip). The strip reads `7 OF 10 TONIGHT · RESETS 00:00 UTC` from the download response. At 2 left it turns crimson and shows "Sign in at the ticket office (free, more tickets)" or "Use the Subdl slot".
3. Unknown file: the marquee spells the cleaned filename and one bulb stays dark.
- **Why it delights:** the sign remembers what you watched; the quota — the app's ugliest constraint — becomes a small ritual instead of an error.

---

## 9. Screen-by-screen

Legend: `▓` lit tungsten · `░` velvet surface · `▒` booth glass · `·` bulbs · `[ ]` touch target. Wireframes are portrait phone unless labelled.

### 9.1 Lobby (Home / Now Showing)

```
PHONE (portrait)                              DESKTOP (Windows, frameless, Mica in Lobby only)
┌──────────────────────────────┐              ┌───────────────────────────────────────────────────────────┐
│ sky band (time of day) ····· │              │ ····· THE THIRD MAN ····· 1949 ·····            · · ·     │  <- marquee box = title bar
│ ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓ │              │ ───────────── crimson 1px trim ───────────────────────────│
│ ┃  ·  THE THIRD MAN  ·     ┃ │  marquee     │ sky band                                                  │
│ ┃      1949 · NOW SHOWING  ┃ │              │                                                           │
│ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛ │              │   ░░░░░░░   ░░░░░░░   ░░░░░░░   ░░░░░░░   ░░░░░░░         │
│ ───── crimson 1px trim ───── │              │   ░poster░  ░poster░  ░poster░  ░poster░  ░poster░        │
│                              │              │   ░ 2:3  ░  ░      ░  ░      ░  ░      ░  ░      ░        │
│  ~~~~~~ horizon 62% ~~~~~~~  │              │   ▓▓▓░░░░   ▓▓▓▓▓░░   ░░░░░░░   ▓░░░░░░   ░░░░░░░  <- resume sprocket track
│  ░░░░░░░ ░░░░░░░ ░░░░░░░ ░░  │  velvet rail │   The Third Man  Chungking…  Paddington  …              │
│  ░ 3:4 ░ ░ 3:4 ░ ░ 3:4 ░ ░░  │  snap-scroll │   1949 · 1h33 · MKV · EN ✓                                │
│  ░     ░ ░     ░ ░     ░ ░░  │              │                                                           │
│  ▓▓▓░░░░ ▓▓▓▓▓░░ ░░░░░░░ ░░  │  resume      │              ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐                 │
│  Third Man Chungk… Paddi…    │              │              │  drop a print here  ·  or  Open  │        │  <- beam idle cone behind
│                              │              │              └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘                 │
│         ┌ ─ ─ ─ ─ ─ ┐        │  doors/drop  │                                                  ♪ ◐ ⚙     │  <- room tone, theme, settings bulbs
│         │  ▌ ▐   ▌ ▐ │  [▓▓] │  Open disc   │ Subtitles by OpenSubtitles.com · TMDB logo + notice        │
└──────────────────────────────┘              └───────────────────────────────────────────────────────────┘
```

- **Components:** Marquee sign (letters, bulb row, crimson trim), Sky band, Velvet rail + Now Showing card (poster or 25 %-lit frame grab, resume sprocket track, `±` sync badge, `EN ✓` chip), Open disc (64 px tungsten, bottom-right, thumb zone), Doors drop target (whole dark area; dragging over widens the beam), Attribution line, three small bulbs (room tone · theme · settings). Desktop adds a `?` cue-sheet overlay and a 2-layer parallax (walls ±6 px, screen 0) at ≤ 1°.
- **States:** *Empty* — marquee reads `MARQUEE`, the rail is replaced by one sentence "Drop a film on the doors, or press Open", the beam idles; *Loading library* — cards as 25 %-lit frames with a 240 ms shimmer, no spinner; *Error (file gone)* — the card dims to 40 % with `PRINT MISSING` in mono and a `Locate` link; *Success* — a card's resume track fills; *Drag-over* — beam widens, doors outline brightens to `--accent`.
- **Gestures:** horizontal snap-scroll on the rail; tap card = house lights down; long-press card = context (Play from start · Find subtitles · Remove); pull-down on the rail = rescan library (Android); predictive back exits.

### 9.2 Threading (Identify & Subtitle)

```
PHONE (portrait, dimmed room)                 DESKTOP
┌──────────────────────────────┐              ┌───────────────────────────────────────────────────────────┐
│ REEL 01 · THREADING          │  folio       │ REEL 01 · THREADING                            Skip subs │
│                              │              │                                                           │
│          ╭────────╮          │              │      ╭──────────╮      EN ✓MATCH BluRay.x264-AMIABLE [▓]  │
│         ╱    ▓▓    ╲         │  leader      │     ╱     ▓▓     ╲     ░ 12 431 dl · 23.976 fps · not HI  │
│        │     ▓▓     │        │  sweep       │    │      ▓▓      │    ░ EN  BluRay.x264-AMIABLE 51 000 dl│
│        │  ▓▓▓▓▓▓▓▓  │        │  numeral 2   │    │   ▓▓▓▓▓▓▓▓   │    ░ HI  BluRay-AMIABLE 902 dl · 25fps│
│         ╲          ╱         │              │     ╲            ╱     ░ EN  WEB-DL.H264-NTb 4 102 dl · HI│
│          ╰────────╯          │              │      ╰──────────╯      ░ Also from Subdl ─────────────────│
│  8e245d9679d31e12 · 1.42 GB  │  mono        │  8e245d9679d31e12 · 1.42 GB · 23.976 fps                  │
│  23.976 fps                  │              │                                                           │
│ ──────────────────────────── │              │  ▐ 7 OF 10 TONIGHT ▐▐▐▐▐▐▐ · resets 00:00 UTC             │
│ ░ ● MATCH  EN  x264-AMIABLE  │  candidates  └───────────────────────────────────────────────────────────┘
│ ░   12 431 dl · 23.976 · —HI │
│ ░   EN  x264-AMIABLE · 51 000│
│ ░   HI  BluRay-AMIABLE · 25  │
│ ░   EN  WEB-DL-NTb · 4 102 dl│
│ ──────────────────────────── │
│ ▐ 7 OF 10 TONIGHT ▐▐▐▐▐▐▐    │  ticket strip
│ [ Skip subtitles ]           │
└──────────────────────────────┘
```

- **Components:** Leader (numeral + sweep + hash line), Candidate row (language code mono, MATCH bulb, release name, downloads tabular, fps, HI ear glyph, auto-selected top row lit), Ticket strip, Skip link, Subdl section, Manual search field (appears on stall).
- **Order is the score, and the list is never filtered.** The four rows above are the frozen golden fixture `test/fixtures/os/candidates-third-man.json` drawn in the only order it can legally appear: **A** `…1080p.BluRay.x264-AMIABLE` hash-matched, 12 431 dl (1414.09) → **D** the same release without a hash, 51 000 dl (414.71) → **C** `…1949.BluRay-AMIABLE`, 902 dl, HI, 25 fps (232.96) → **B** `…1080p.WEB-DL.H264-NTb`, 4 102 dl, HI (63.61). D above B is the case R4 exists to protect — `x264` and `H264` are different tokens, so the same-group BluRay encode outranks the WEB-DL even with no hash. If a wireframe, a widget or `design/preview.html` ever draws B above C or D, it is showing a state the scorer cannot produce (ARCHITECTURE §6.3, TESTING §2.4, IMPLEMENTATION-PROMPT §6.4).
- **States:** *Hashing* ("3"), *Searching* ("2"), *Downloading* ("1"), *Match* (green bulb + 2-pop), *By name* (`--warning` label `CHECK SYNC`), *Stalled* (sweep frozen; fallback rows slide in), *Quota* (strip crimson, sentence "No tickets left tonight — sign in for more, or use the Subdl slot"), *Offline* ("2" stalls; "Play without subtitles" lit), *File < 128 KiB* (skip hash, go straight to filename search — no error shown).
- **Gestures:** tap any row overrides the auto-pick; swipe down / predictive back = skip; on desktop `Esc` skips, `Enter` accepts.

### 9.3 Auditorium (Player)

```
PHONE (landscape, controls shown)                          DESKTOP (frameless; folio = title bar; controls shown)
┌────────────────────────────────────────────────┐         ┌───────────────────────────────────────────────────────────┐
│ REEL 01 · 01:12:44 · −01:28:19        ● ✓     ▏│         │ REEL 01 · THE THIRD MAN · 01:12:44 · −01:28:19    · · ·   │
│▕                                              ▏│         │                                                           │
│▕▓        ┌────────────────────────────┐      ▓▏│ edge    │  wall glow  ┌───────────────────────────────────┐  wall  │
│▕▓        │                            │      ▓▏│ dimmers │             │                                   │  glow  │
│▕▓        │        the picture (#000)  │      ▓▏│ bright/ │             │          the picture (#000)       │        │
│▕▓        │      subtitles by libass   │      ▓▏│ volume  │             │        subtitles by libass        │        │
│▕         └────────────────────────────┘       ▏│         │             └───────────────────────────────────┘        │
│  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  │ aisle   │  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  · │
│ ▯▯▯▯▯▯▯▯▯▯▯▯[▓▓▓]▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯ │ gate    │ ▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯[▓▓▓▓]▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯▯ │
│ [◀10] [ ▶ ] [10▶]  SYNC +0.00  [CC] [♪] [⛶] [⧉]│         │ [◀10] [ ▶ ] [10▶]  SYNC +0.00  [CC] [♪] [1.0×] [A–B] [⛶] [?]│
└────────────────────────────────────────────────┘         └───────────────────────────────────────────────────────────┘
Portrait phone: picture at top (16:9, letterboxed #000), wall glow around it, folio above, gate + controls in the bottom 22 % (thumb zone).
```

- **Components:** Folio (title/reel/timecode/remaining), Picture, Wall glow (bias light), Aisle lights (row of 5 px tungsten dots that brighten as the pointer/thumb approaches), Film gate seek, Transport marks (±10 s, play/pause), Sync readout, Tracks (CC = subtitle tracks, ♪ = audio), Speed, A–B loop (desktop), Fullscreen, PiP (Android), Cue sheet `?` (desktop), Exit-sign bulb (green when a subtitle is attached *and* saved beside the file).
- **States:** *Idle-hidden* (all chrome gone after 2400 ms; folio 40 %); *Paused* (aisle lights hold at 60 %, the beam narrows 10 %, wall glow freezes); *Buffering* (the gate's frame flickers at 2 Hz — no spinner); *No subtitle* (CC mark hollow); *Error* (picture goes to `--bg`, one sentence in `--ink`, actions beneath — never a red banner); *PiP* (chrome removed; folio in the PiP title).
- **Gestures (Android):** single tap = controls; double-tap left/right third = ∓10 s (the gate visibly jumps); long-press = 2× while held (folio reads `2.0×`); vertical drag on the left/right edge = brightness/volume drawn as vertical filament bars with a mono readout; horizontal drag anywhere on the picture = scrub with the gate following; pinch = fit/fill; predictive back = house lights up. **Keyboard (Windows):** Space, ←/→ 5 s, Shift+←/→ 30 s, ↑/↓ volume, F fullscreen, S subtitle tracks, A audio tracks, J/K sync ∓50 ms, `,`/`.` frame-step, L A–B loop, `[`/`]` speed, P PiP, `?` cue sheet, Esc back.

### 9.4 Subtitle Booth (sheet)

```
PHONE (rises to 70 %, booth glass over the paused frame)   DESKTOP (popover 420 px, anchored to CC)
┌──────────────────────────────┐                          ┌──────────────────────────┐
│  (paused frame visible)      │                          │ TRACKS                   │
│ ▒▒▒▒▒▒▒▒▒▒ ─── ▒▒▒▒▒▒▒▒▒▒▒▒ │  handle                  │ ● EN  Marquee · synced ✓ │
│ ▒ TRACKS                    ▒│                          │   EN  embedded (PGS)     │
│ ▒ ● EN  Marquee · synced ✓  ▒│  attached                │   Off                    │
│ ▒   EN  embedded (PGS)      ▒│                          │ ─────────────────────── │
│ ▒   Off                     ▒│                          │ STYLE  A  A  A  ▢ outline│
│ ▒ ───────────────────────── ▒│                          │ POSITION  ▁ ▂ ▃          │
│ ▒ STYLE   A  A  A   outline ▒│  live on frame           │ ─────────────────────── │
│ ▒ POSITION  ▁  ▂  ▃         ▒│                          │ SYNC ─2.00 ─1.00 ▲ +1.00 │
│ ▒ ───────────────────────── ▒│                          │ ─────────────────────── │
│ ▒ SYNC  ─1.00  ▲ +0.00 +1.00▒│  sync rule               │ Find another print  ▐7▐  │
│ ▒ ───────────────────────── ▒│                          └──────────────────────────┘
│ ▒ [ Find another print ]  ▐7▐│  re-search + tickets
└──────────────────────────────┘
```

- **Components:** Track list (external, embedded, off), Style presets (size S/M/L, outline on/off, applied live via mpv `sub-*` / JASSUB overrides), Position (bottom / lower-third / top), Sync rule, "Find another print" (re-runs filename → Subdl without leaving the sheet), Ticket count, Language + HI preferences link.
- **States:** *Loading* (rows shimmer 240 ms), *Empty* (only embedded/off + "Find a print"), *Quota* (button reads "No tickets — Subdl slot"), *Success* (row gains `synced ✓` in `--success`).
- **Gestures:** drag handle 1:1; velocity dismiss; predictive back closes; scroll inside; never exceeds 70 % so the frame stays visible.

### 9.5 Ticket Office (Account, settings, attribution)

```
PHONE                                          DESKTOP (two columns)
┌──────────────────────────────┐               ┌───────────────────────────────────────────────────────────┐
│ ‹ TICKET OFFICE              │               │ ‹ TICKET OFFICE                                           │
│ ░ OPENSUBTITLES              │               │ ░ OPENSUBTITLES             ░ PROJECTION                  │
│ ░ signed in as rahul  ▐7▐▐▐▐ │  ticket strip │ ░ signed in · ▐7 OF 10▐▐▐▐  ░ Hardware decode   auto-safe │
│ ░ resets 00:00 UTC · sign out│               │ ░ Languages  EN · HI · TA   ░ Interpolation     off       │
│ ░ Languages  EN · HI · TA    │               │ ░ Hearing-impaired  prefer  ░ Shaders (Win)    Anime4K ▾  │
│ ░ Hearing-impaired   prefer  │               │ ░ Save beside file   on     ░ Subtitle font    Noto Sans  │
│ ░ Save beside file      on   │               │ ░ Subdl slot  key ····· on  ░ Indic fonts     download    │
│ ░ Subdl slot   key ····· on  │               │ ░ AMBIENCE                  ░ ABOUT                       │
│ ░ AMBIENCE                   │               │ ░ Room tone  on · Bias light on · Beam on · Matinee auto  │
│ ░ Room tone            on    │               │ ░ Sounds on · Haptics on                                   │
│ ░ Bias light (Android) off   │               │ ░ Subtitles by OpenSubtitles.com                           │
│ ░ Beam                 on    │               │ ░ [TMDB logo] This product uses TMDB and the TMDB APIs but │
│ ░ Matinee lobby      auto    │               │ ░ is not endorsed, certified, or otherwise approved by TMDB│
│ ░ Sounds · Haptics    on     │               │ ░ libmpv · ffmpeg · libass — LGPL notices + source links   │
│ ░ ABOUT · attribution        │               │ ░ Fonts: Big Shoulders, Geist, Noto Sans (OFL) · Marquee MIT│
└──────────────────────────────┘               └───────────────────────────────────────────────────────────┘
```

- **Components:** Sign-in row (username/password inputs with underline only; on submit the ticket stub "tears" in; JWT stored in `flutter_secure_storage` / WebCrypto AES-GCM, password never kept), Ticket strip, Language chips, Toggle bulbs (lit = on), Select rows, Attribution block (typeset, not hidden), Version + licence line.
- **States:** *Signed out* (strip shows `ANONYMOUS · 5 PER DAY PER IP` in `--ink-muted`), *Signing in* (stub outline draws over 480 ms), *401 expired* (row reads "Ticket expired — sign in again" in `--warning`), *Error* (one sentence under the form in `--danger`, field underline turns `--danger`).
- **Gestures:** standard scroll; predictive back.

### 9.6 No Print (web codec fallback) and Marquee Lite landing

```
LITE LANDING (web, Auditorium)                 NO PRINT (web)
┌──────────────────────────────┐               ┌──────────────────────────────┐
│ ····· MARQUEE LITE ·····     │               │ REEL 01 · THREADING          │
│                              │               │            ·  (beam narrows  │
│      ╲    beam idle    ╱     │               │            ·   to a pinpoint)│
│   ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐    │               │ ░ This print can't be        │
│   │   DROP A FILM HERE   │   │               │ ░ projected here.            │
│   │      or  [ Open ]     │  │               │ ░ MKV · HEVC · AC-3          │
│   └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘    │               │ ░ This browser has no AC-3   │
│ This browser can play:       │  honest line  │ ░ decoder.                   │
│ MP4/H.264 · WebM/VP9/AV1 ·   │  from         │ ░ [ Try the WebCodecs path ] │
│ HEVC ✓ · AC-3 ✗ · MKV partial│  canPlayType  │ ░ [ Open in Marquee for      │
│ Open in Marquee for Windows  │               │ ░   Windows / Android ]      │
│ / Android →                  │               └──────────────────────────────┘
└──────────────────────────────┘
```

- **Components:** Drop frame (dashed `--border-strong`, 12 px radius), Open button, Capability line (from `canPlayType` / `VideoDecoder.isConfigSupported`), Release links, No-Print card (container/codecs in mono, one-sentence reason, two actions).
- **States:** *Drag-over* (beam widens, frame turns `--accent`), *Probing* (leader "3" while `isConfigSupported` runs), *WebCodecs path* (movi-player/mediabunny mounted; folio reads `WEBCODECS`), *Unsupported* (No Print card; never a red banner).

---

## 10. Component inventory

| Component | Variants | States |
|---|---|---|
| Marquee sign | idle (`MARQUEE`), now-showing, filename-fallback (one bulb dark), title-bar (desktop) | bulbs on / painted (Matinee) / embers (house down); warming |
| Bulb | 5 px tungsten, aisle light, window control (desktop ×3), toggle (settings), exit-sign (green), MATCH | off / on / warming / flicker (night) |
| Beam (shader) | idle cone, wide (playback), pinpoint (No Print), static (reduced motion / context lost) | — |
| Sky band | dawn / day / dusk / night; 6 % (Auditorium) or 100 % (Matinee) | — |
| Velvet rail + Now Showing card | poster (TMDB w342/w500) / frame-grab 25 % lit; 3:4 phone, 2:3 desktop | default / hover (surface-2, lift 0) / pressed / missing / drag-over |
| Resume sprocket track | under card; in gate track | empty / partial / complete |
| Open disc | 64 px tungsten | default / pressed (accent-ink flashes) / drag-over |
| Folio | lobby (`PROGRAMME`), auditorium (`REEL 01 · tc · −rem`), threading | 100 % / 40 % (auto-hide) |
| Leader | numeral 3/2/1, sweep, hash line | sweeping / stalled / done / reduced (crossfade) |
| Candidate row | OpenSubtitles / Subdl / embedded | auto-picked / match / by-name / HI / selected / downloading / attached |
| Ticket strip | inline (threading), full (ticket office), anonymous | n left / tearing / 2 left (crimson) / exhausted |
| Film gate seek | phone 56 px / desktop 40 px; with thumbnails / timecode-only | idle / dragging / FINE / buffering flicker / detent flash |
| Transport mark | ±10, play/pause, CC, ♪, speed, A–B, fullscreen, PiP, `?` | default / hover (halo) / active (lit) / disabled (ink-faint) |
| Sync rule + readout | inline readout; expanded ruler | hidden / dragging / snapped / remembered (`±` badge) |
| Edge dimmer | brightness (left), volume (right) | hidden / active with mono readout |
| Booth sheet | 70 % (phone), popover 420 px (desktop) | rising / open / dragging / dismissed |
| Toggle bulb | settings on/off | on / off / focused |
| Underline input | text, password, search | default / focus (accent underline 2 px) / error (danger) |
| Chip | language code, `EN ✓`, `±0.35`, HI ear | static / selected |
| Sentence banner | error / info under the leader or in the picture area | — (never red-filled) |
| Cue sheet | desktop `?` overlay, mono two-column | — |
| Attribution block | lobby footer line; ticket-office full | — |

---

## 11. Iconography, illustration, imagery

- **Icons:** Lucide (ISC) at 1.5 px stroke, 20 px, coloured `--ink-muted` (idle) or `--accent` (active): `play`, `pause`, `captions`, `audio-lines`, `maximize-2`, `picture-in-picture-2`, `repeat` (A–B), `gauge` (speed), `settings-2`, `ticket`, `ear`, `x`, `arrow-left`. Skip marks are `◀10 / 10▶` text-marks in Geist Mono, not icons. Transport marks are glyph-plus-halo, never buttons with backgrounds.
- **Illustration:** none. The room is drawn by light. The only pictorial elements are the marquee, the film strip and the leader — all rendered from CSS/SVG/shader, no bitmap assets.
- **Imagery:** TMDB posters/backdrops (optional, BYO key or CI-injected; non-commercial; TMDB logo + required notice; cache ≤ 6 months; no ML) — https://www.themoviedb.org/api-terms-of-use. Frame grabs from the user's own file otherwise. No stock photography anywhere. Reference photos in this document (Wikimedia Commons) are for the moodboard only, never shipped.
- **Wordmark:** `MARQUEE` in Big Shoulders 900 with 7 bulbs beneath; app icon = a single lit bulb on the crimson-trimmed marquee box.

---

## 12. Sound & haptics

All sound is optional, off during playback, respects the OS silent switch and one "Sounds" bulb. Web: Howler.js (MIT) sprites + Web Audio synthesis; Flutter: `flutter_soloud` (MIT) or `audioplayers` (MIT).

| Event | Sound | Source |
|---|---|---|
| Lobby room tone | 16-bit projector-motor loop, −30 dB, high-passed 120 Hz, starts on first gesture, mutable | freesound.org CC0 filter ("projector loop") or Kenney (CC0) — https://freesound.org/search/?q=projector&license=Creative+Commons+0 · https://kenney.nl/assets/ui-audio |
| House lights down | 900 ms sine sweep 200 → 60 Hz, −24 dB | synthesised, no asset |
| 2-pop (hash match, subtitle attached) | 1 kHz sine, 33 ms, −18 dB | synthesised |
| Detent (gate chapter, sync rule) | 4 ms filtered-noise click | synthesised |
| Ticket tear | short paper rip, −20 dB | Kenney UI Audio (CC0) or synthesised noise burst |
| Sheet rise / dismiss | none | — |

**Haptics (Flutter `HapticFeedback` on native; the web tier has none — Marquee's Android app is Flutter, not Capacitor):** `lightImpact` when controls reveal; `selectionClick` per gate detent, sync-rule detent and frame-step; `mediumImpact` on hash match, when a subtitle attaches, and on ticket tear; `heavyImpact` never; `vibrate` (notification) on quota exhaustion only. Never vibrate during playback for anything else. One "Haptics" bulb in the Ticket Office; default on for phone.

---

## 13. Accessibility rules

- **Contrast:** all text tokens ≥ 4.5 : 1 on their allowed surfaces (tables in §4); `--ink-faint` and `--danger` are ≥ 18 px on `--surface-2`; crimson `--accent-2` is never text on dark — use `--accent-2-lit`. Controls over the picture always sit on the wall (`--bg`), never on the video, and use `--ink`/`--accent` on `#000` (≥ 13 : 1). Subtitle default style: Noto Sans, white with 2 px black outline and 40 % shadow (libass `BorderStyle=1`).
- **Focus:** 2 px `--focus` ring, 2 px offset, on every interactive element including transport marks and the gate; visible in both palettes; never removed on `:focus-visible`.
- **Motion:** §7 reduced-motion table; `MotionConfig reducedMotion="user"` on the web; `MediaQuery.disableAnimations` on Flutter; no autoplaying shader when reduced.
- **Touch targets:** ≥ 44 × 44 px; the gate is 56 px; edge dimmers are 48 px wide; aisle lights are decorative and non-interactive (transport marks are the targets).
- **Screen readers:** the leader announces once per phase ("Reading file", "Searching subtitles", "Downloading English subtitles", "Subtitles attached, in sync") via `aria-live="polite"` / `SemanticsService.announce`, never per sweep frame; the marquee announces the final title once, not per bulb; the film gate is `role="slider"` with `aria-valuetext` as a timecode; the sync rule is a slider with `aria-valuetext="plus 0.35 seconds"`; bulbs that are toggles are `role="switch"`; the ticket strip has `aria-label="7 of 10 downloads left tonight"`; decorative bulbs/beam are `aria-hidden`.
- **Keyboard:** everything reachable; the cue sheet lists all shortcuts; `Esc` always goes one lighting state up.
- **Language:** UI in English; subtitle language names shown as ISO code + English exonym.

---

## 14. Android-specific notes (Flutter tier)

- **Edge-to-edge:** `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)`; status bar and navigation bar transparent with light icons in the Auditorium, dark icons in the Matinee lobby. `SafeArea` for the marquee (top) and controls (bottom); the picture itself extends under the cutout in landscape (`LayoutMode.shortEdges`).
- **Playback:** `SystemUiMode.immersiveSticky` while controls are hidden; keep-screen-on via `wakelock_plus`; brightness override via `screen_brightness` (per-app, restored on exit); PiP with `android:supportsPictureInPicture="true"` and `resizeableActivity`; audio focus handled by media_kit; `configChanges` for orientation so the player is not rebuilt.
- **Gesture navigation:** predictive back enabled (`android:enableOnBackInvokedCallback="true"`); the Booth sheet and Threading screen register back callbacks so the system preview shows the room, not a blank page; the horizontal scrub gesture starts 24 px inside the left/right edges to avoid the back gesture.
- **Safe areas:** edge dimmers sit inside the system gesture insets; the Open disc is 24 px above the navigation-bar inset.
- **Splash:** `flutter_native_splash` with background `#07060A` and a single lit bulb (72 dp) centred; Android 12+ `windowSplashScreenAnimatedIcon` uses the bulb with a 300 ms warm-up.
- **Adaptive icon:** foreground = the marquee box (crimson 1 px trim, one lit bulb, `M` in Big Shoulders 900 `--ink`) on a transparent layer; background = `#07060A`; monochrome layer = the bulb silhouette. Legacy icon uses the same at 48 dp.
- **Files:** SAF (`file_picker`) for opening; `MediaStore` scan for the library with a persisted permission; subtitles saved beside the file when the URI is writable, otherwise into app storage with a "beside file" fallback note.
- **Performance:** bias light opt-in on Android until measured (RESEARCH §8); beam shader capped at DPR 1.0 and paused during playback; `--split-per-abi`, arm64-v8a primary.
- **Fonts:** bundle `NotoSans-Regular.ttf` (libass, `libassAndroidFontName: 'Noto Sans'`), Big Shoulders Display, Geist, Geist Mono TTFs in `assets/fonts/`.

---

## 15. CSS design tokens (ready to paste — `src/styles/tokens.css`)

Shared by the Vite web tier and emitted to `tokens.dart` by `scripts/tokens.mjs` so both tiers match.

```css
:root {
  /* ---- Auditorium (default, dark) ---- */
  --bg: #07060A;
  --bg-elevated: #120E15;
  --surface: #1B1620;
  --surface-2: #26202B;
  --ink: #F3E9DA;
  --ink-muted: #A89C8C;
  --ink-faint: #8C8276;
  --accent: #FFC56E;
  --accent-ink: #1A1006;
  --accent-2: #A3252F;
  --accent-2-lit: #E0525C;
  --success: #5FD48A;
  --warning: #F5A05F;
  --danger: #E5484D;
  --border: #2A2330;
  --border-strong: #3D3446;
  --focus: #FFD68A;

  /* semantic / derived */
  --picture-bg: #000000;
  --wall-glow: radial-gradient(60% 60% at 50% 50%, color-mix(in oklch, var(--focus) 6%, transparent), transparent);
  --bulb-halo: 0 0 6px 1px color-mix(in oklch, var(--accent) 55%, transparent);
  --booth-glass: color-mix(in oklch, var(--bg-elevated) 78%, transparent);
  --glass-blur: 24px;
  --sky-dawn: #3A2A2E; --sky-day: #2A2E3A; --sky-dusk: #2F2438; --sky-night: #0B0A10;
  --house: 1;                 /* 1 = house up, 0 = dark; tweened by house-down/up */
  --grain-opacity: 0.04;      /* lobby + sheets only; 0 in the auditorium */

  /* ---- Typography ---- */
  --font-display: "Big Shoulders Display Variable", "Big Shoulders Display", Impact, "Arial Narrow", sans-serif;
  --font-body: "Geist Variable", Geist, system-ui, "Segoe UI", sans-serif;
  --font-mono: "Geist Mono Variable", "Geist Mono", ui-monospace, Consolas, monospace;
  --text-xs: 0.75rem;
  --text-sm: 0.875rem;
  --text-base: 1rem;
  --text-lg: 1.125rem;
  --text-xl: 1.375rem;
  --text-2xl: 1.75rem;
  --text-3xl: 2.25rem;
  --text-4xl: clamp(3rem, 6vw, 4rem);
  --text-5xl: clamp(5rem, 14vw, 9rem);
  --leading-tight: 1.05;
  --leading-body: 1.5;
  --tracking-display: 0.06em;
  --tracking-display-lg: 0.02em;
  --tracking-label: 0.08em;

  /* ---- Spacing ---- */
  --space-1: 4px;  --space-2: 8px;  --space-3: 12px; --space-4: 16px;
  --space-5: 20px; --space-6: 24px; --space-7: 32px; --space-8: 40px;
  --space-9: 48px; --space-10: 64px; --space-11: 80px; --space-12: 96px;

  /* ---- Radius ---- */
  --radius-sm: 4px;
  --radius-md: 8px;
  --radius-lg: 12px;
  --radius-xl: 20px;
  --radius-full: 9999px;

  /* ---- Elevation (one light source, above and behind) ---- */
  --shadow-1: inset 0 1px 0 rgba(255,255,255,.04), 0 2px 6px rgba(0,0,0,.5);
  --shadow-2: inset 0 1px 0 rgba(255,255,255,.05), 0 8px 24px rgba(0,0,0,.55);
  --shadow-3: inset 0 1px 0 rgba(255,255,255,.06), 0 24px 56px rgba(0,0,0,.65);

  /* ---- Motion ---- */
  --dur-fast: 120ms;
  --dur-base: 240ms;
  --dur-slow: 480ms;
  --dur-house: 900ms;
  --ease-out: cubic-bezier(0.22, 1, 0.36, 1);
  --ease-in-out: cubic-bezier(0.65, 0, 0.35, 1);
  --ease-house: cubic-bezier(0.7, 0, 0.3, 1);
  --ease-spring: linear(0, 0.006, 0.025 2.8%, 0.101 6.1%, 0.539 18.9%, 0.721 25.3%, 0.849 31.5%, 0.937 38.1%, 0.968 41.8%, 0.991 45.7%, 1.006 50.1%, 1.012 55.4%, 1.011 62.6%, 1.006 71.7%, 1);
  --spring-stiffness: 380; --spring-damping: 32; --spring-mass: 1;

  /* ---- Layout ---- */
  --page-max: 1280px;
  --gutter: 24px;
  --margin-phone: 20px;
  --target-min: 44px;
  --gate-height: 56px;
  --controls-idle: 2400ms;

  color-scheme: dark;
}

/* Matinee — Lobby, Booth, Ticket Office only; never while a file is open */
[data-theme="matinee"] {
  --bg: #F1E8D8;
  --bg-elevated: #F8F2E6;
  --surface: #E8DECB;
  --surface-2: #DDD1BC;
  --ink: #2A2226;
  --ink-muted: #5E5350;
  --ink-faint: #605651;
  --accent: #7F4800;
  --accent-ink: #FFF6E6;
  --accent-2: #A3252F;
  --accent-2-lit: #A3252F;
  --success: #186639;
  --warning: #8A4B00;
  --danger: #A8231C;
  --border: #D6CAB5;
  --border-strong: #B9AB93;
  --focus: #7A4A00;
  --sky-dawn: #F5C9A8; --sky-day: #C9D6E8; --sky-dusk: #C8A9D6; --sky-night: #1A1622;
  --bulb-halo: none;
  --shadow-1: 0 1px 2px rgba(42,34,38,.12);
  --shadow-2: 0 6px 18px rgba(42,34,38,.16);
  --shadow-3: 0 18px 40px rgba(42,34,38,.22);
  --grain-opacity: 0.03;
  color-scheme: light;
}

@property --house { syntax: "<number>"; inherits: true; initial-value: 1; }

@media (prefers-reduced-motion: reduce) {
  :root { --dur-house: 240ms; --ease-house: var(--ease-in-out); --ease-spring: var(--ease-out); }
}
```

Flutter mirror (`lib/theme/tokens.dart`, generated): `Tokens.bg`, `Tokens.accent`, … as `Color`; `Tokens.durHouse = Duration(milliseconds: 900)`; `Tokens.easeHouse = Cubic(0.7, 0, 0.3, 1)`; `Tokens.spring = SpringDescription(mass: 1, stiffness: 380, damping: 32)`; `Tokens.textScale` map; fonts registered in `pubspec.yaml` as `Big Shoulders Display`, `Geist`, `Geist Mono`, `Noto Sans`.

---

## 16. Asset checklist

**Fonts (OFL, self-hosted)**
- [ ] `@fontsource-variable/big-shoulders-display`, `@fontsource-variable/geist`, `@fontsource-variable/geist-mono` (web); subset Latin.
- [ ] `assets/fonts/BigShouldersDisplay[wght].ttf`, `Geist[wght].ttf`, `GeistMono[wght].ttf`, `NotoSans-Regular.ttf`, `NotoSans-Bold.ttf` (Flutter); optional Indic Noto downloads.

**Shaders / textures**
- [ ] `beam.frag` (GLSL 460 for Impeller; GLSL ES 300 for OGL) — cone + 3-octave value noise + dust sprites; uniforms `angle`, `width`, `time`, `house`.
- [ ] `grain.frag` or `noise-256.png` (generated, CC0) for the lobby.
- [ ] Static radial-gradient fallback CSS for WebGL context loss.

**Sound (CC0)**
- [ ] `projector-loop.ogg` (freesound CC0 or Kenney), −30 dB, 120 Hz high-pass, seamless loop.
- [ ] `ticket-tear.ogg` (Kenney UI Audio CC0) — or synthesised.
- [ ] Web Audio / soloud synth module for sweep, 2-pop, detent click (no files).

**Icons & brand**
- [ ] Lucide subset listed in §11.
- [ ] App icon: adaptive foreground/background/monochrome SVG → PNGs at mdpi–xxxhdpi; Windows `.ico` (16–256); web `manifest` icons 192/512 + maskable.
- [ ] Splash: `#07060A` + bulb (72 dp) for `flutter_native_splash`.
- [ ] TMDB logo (official SVG, https://www.themoviedb.org/about/logos-attribution) + notice text; OpenSubtitles credit line.

**Docs & legal**
- [ ] LGPL notices for libmpv / ffmpeg / libass with links to `media-kit/libmpv-android-video-build` and `media-kit/libmpv-win32-video-cmake`; MIT licence for the app; font OFL texts in `LICENSES/`.
- [ ] `design/preview.html`: Lobby (night + matinee), Threading mid-sweep, Auditorium with controls, Booth sheet — the visual contract.
- [ ] `scripts/tokens.mjs` → `tokens.css` + `tokens.dart`.
- [ ] Keyboard cue-sheet JSON (single source for the `?` overlay and README).

**Verification before release**
- [ ] Contrast sweep of every text token on every allowed surface (script in `e2e/contrast.spec.ts`).
- [ ] Real-device Android: libass rendering, bias-light battery, beam DPR cap, predictive back on the sheet.
- [ ] Windows: frameless window drag on the marquee title bar, Mica only in the Lobby, opaque black during playback.
- [ ] Reduced-motion pass: leader stalls honestly, no dust, sheets fade.
