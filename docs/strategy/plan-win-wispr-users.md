# Plan: win Wispr Flow users and make SpeakType pay (2026-10-24)

## Summary
- **Position:** "Wispr Flow's feel, but private, smarter to tune and less limited." Local by default, cloud optional with your own key, no account, no word cap. (Owner decision 2026-10-24.)
- **Model:** free unlimited local dictation forever; Pro adds AI cleanup and cloud engines. Pro is $6/month, $48/year, or $89 once (3 Macs). 14-day Pro trial. Code stays open source (MIT); the signed app plus Pro license is what people pay for. (Owner decision 2026-10-24; exact prices are a proposal.)
- **Why it can work:** Wispr's top complaints are price ($144/yr), outages and lost transcripts, and cloud-only privacy (an April 2026 teardown showed app/URL logging). Free local apps exist but lack cleanup. Nobody owns "private + polished + cleanup + pay once".
- **Biggest risk:** reliability. If SpeakType ever loses a dictation or feels slow, the pitch collapses. Reliability work comes before new features.
- **Blocking for revenue:** Polar products and checkout links do not exist yet, and the app has no Pro gating switched on.

## Phase 1 — Trust (now, in progress)
Goal: SpeakType never loses words and feels instant.
1. Fix the 12 confirmed core bugs from the 2026-10-24 audit (lost audio on failure, clipboard overwritten, short presses ignored, silent paste failure, Esc swallowed, mic left on, Fn tap not retried, and more).
2. Remove fixed delays: 0.5 s before every paste, 0.3 s cold start that clips first words.
3. Keep every recording in history, mark failures, offer Retry.
4. Retry cloud requests on timeouts and rate limits.
5. "Paste last transcript" in the menu bar.

## Phase 2 — Make money (next, needs owner)
1. Owner: create Polar products (Pro monthly, Pro yearly, Lifetime) and send the three checkout links plus organization ID.
2. Wire links into the site (`NEXT_PUBLIC_CHECKOUT_*`) and the app (`PolarOrganizationID`, `PolarPurchaseURL`).
3. Turn on Pro gating in the app: AI cleanup, cloud engines, file transcription, export. Local dictation stays free and unlimited.
4. One quiet upgrade prompt at the moment a free user tries a Pro feature. No nag banners.
5. Deploy the new site and point a domain at it.

## Phase 3 — Smarter than Wispr (features that justify Pro)
Ranked by what Wispr users praise and what they lack:
1. **Personal dictionary**: names and jargon spelled right (fed as Whisper prompt + replacements). Wispr users love this.
2. **Styles per app**: Professional in Mail, Message in Slack, raw in the terminal. Wispr's version is English and desktop only; ours works in every language.
3. **Faithful by default, cleanup levels**: answers "it rewrites what I said".
4. **Backtrack**: "no wait, Tuesday" keeps only the correction.
5. **Snippets**: say a cue, get saved text.
6. **Voice edit selection**: select text, say "make it shorter".
7. **Streaming / live preview** with a fast local model (Parakeet) for long dictations.

## Phase 4 — Polish the app UI
The audit lists inconsistencies (two color palettes, eight button styles, hardcoded sizes, a recorder overlay where errors look like progress, nine settings sections in one scroll, onboarding without back/progress). Proposed order, each needs a quick owner look before changing visible design:
1. Recorder overlay: distinct error state, "Inserted" confirmation, visible cancel.
2. Onboarding: progress dots, Back, real Skip, offer the cloud engine too.
3. Settings: group into Basics / Writing / Engines / Advanced.
4. One palette, one primary button, one copy-feedback pattern.

## Growth
- Comparison page "Wispr Flow alternative" (built) for search traffic.
- Post on r/macapps, Hacker News (Show HN: open-source, local Wispr Flow alternative), Product Hunt.
- Publish real idle RAM numbers once measured.
- Student discount later; Wispr offers 50%.

## Open owner decisions
1. Final prices (proposal: $6/mo, $48/yr, $89 lifetime).
2. Should AI cleanup be on by default for new users? It adds 0.5–3 s per dictation when it runs in the cloud.
3. Keep the mic warm between dictations for an instant start? Faster, but the orange mic dot stays on.
4. Domain for the site.

Research: [wispr-flow-research-2026-10.md](wispr-flow-research-2026-10.md).
