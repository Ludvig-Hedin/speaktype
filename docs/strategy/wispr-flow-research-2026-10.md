# Wispr Flow and competitors — research (2026-10-24)

Reddit, G2 and Product Hunt blocked automated reading. Wispr's Trustpilot profile was removed for guideline violations. Sources used: iOS App Store, Hacker News, Wispr's own pages, a technical teardown, competitor sites (marked where biased).

## Wispr Flow

| Tier | Monthly | Annual | Notes |
|---|---|---|---|
| Free | $0 | $0 | 2,000 words/week on desktop (~15 min speech) |
| Pro | $15 | $12/mo ($144/yr) | Unlimited words, shared dictionary/snippets, 14-day trial |
| Growth | ~$23 | ~$18 | SSO, HIPAA (page ambiguous) |
| Enterprise | Custom | — | |

Source: https://wisprflow.ai/pricing. Cloud only: "Transcription always happens in the cloud" (https://wisprflow.ai/privacy). Mac, Windows, iOS, Android. Raised $280M at $2B valuation, Aug 2026.

Features: AI auto edits, backtrack, personal dictionary, snippets, styles per app (English, desktop only), whisper mode, IDE file tagging, context awareness, notetaker. Command Mode reportedly Pro only (unverified).

## What users love
1. Cleanup quality: "shockingly good", rewrites instead of only transcribing.
2. Effortless, saves time.
3. Accessibility (RSI, ADHD, dyslexia).
4. Personal vocabulary.
5. Cross-device sync.
6. Feeding context into AI tools.

## Complaints, ranked
1. Price / subscription fatigue (top HN theme). "I absolutely will not pay a yearly fee of $150."
2. Reliability: 75+ outages since Dec 2025 (StatusGator via Voibe, competitor source). "it keeps on losing my transcription."
3. Privacy: April 2026 teardown found system-wide key tap, app/URL logging, reading on-screen text (https://wensenwu.com/thoughts/wispr-flow-investigation). HN: "Wispr Flow Is Tracking Every App/URL You Visit".
4. Quality drops after trial (HN, Oct 2026).
5. Rewrites what you said instead of transcribing.
6. Heavy: ~750–800 MB RAM idle (secondhand).
7. Tight free cap.
8. No real support.

## Competitors

| App | Local? | Model | Price |
|---|---|---|---|
| Superwhisper | Yes + cloud | Sub + lifetime | $8.49/mo, ~$85/yr, ~$250 lifetime (unverified) |
| MacWhisper | Yes | One-time | ~€59 (unverified) |
| VoiceInk | Yes, open source | One-time | $25 / $39 / $49 (1/2/3 Macs) |
| Aqua Voice | Cloud | Sub | $10–12/mo |
| Willow | Cloud | Sub | $12–15/mo |
| Spokenly | Yes + BYOK | Free + one-time + sub | Local+ $29 once, Pro $99.99/yr |
| Voibe | Mac on-device | Sub + lifetime | $99/yr, $199 lifetime |
| Monologue | Partly | Sub | $144/yr |
| Handy | Yes, open source | Free | $0, no cleanup |
| Apple Dictation | Yes | Free | No cleanup |

Plain local push-to-talk is now a free commodity (many open-source clones in 2026). The value is in cleanup, reliability and polish.

## Gaps SpeakType can own
1. Private and local *with* good cleanup (local Whisper + local LLM). Free local apps lack cleanup; Wispr has cleanup only in the cloud.
2. Polished app with a one-time price option.
3. Reliability as a feature: no outages, never lose a recording.
4. Faithful mode by default, with cleanup levels.
5. Light and native (Swift, not Electron).
6. Wispr's Pro features (per-app styles in any language, dictionary, snippets) for less.
7. No account, no word caps.
8. Bring-your-own-key cloud fallback.

Unverified: Reddit sentiment, G2/Product Hunt ratings, ban/CTO-apology story, Superwhisper lifetime price, MacWhisper price.
