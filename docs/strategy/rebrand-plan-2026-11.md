# Rebrand and release plan (2026-11-24)

Owner ask (2026-11-24): release SpeakType for others under its own name, logo and site. Probably not a SaaS: local models or bring-your-own-key, likely open source. Make it as polished as Wispr Flow, less "Apple default", less microcopy.

Visual version with logos and app sketches: `output/brand-plan-2026-11-24/index.html` (local, ignored).

## Market facts (checked 2026-11-24)
- Original SpeakType (karansinghgit/speaktype, MIT, Karan Singh): 600 stars, 82 forks, ~4,560 release downloads, site tryspeaktype.com (Vite/React, Supabase, PostHog, beta signup, payments code). Also on the Mac App Store.
- Open-source rivals: Handy 40k stars (MIT, free, offline, cross-platform), OpenWhispr 12.2k (MIT, local + BYOK), VoiceInk 7.2k (paid one-time builds, $29-49).
- Paid: Wispr Flow $12-15/mo cloud only ($280M raise at $2B, Aug 2026); Superwhisper $8.49/mo or ~$250 lifetime; Aqua Voice $8-10/mo.
- Plain local push-to-talk is a free commodity. Value is polish, reliability, cleanup quality.

## Positioning (proposal)
"Wispr Flow feel, nothing leaves your Mac." Three wedges: craft/feel (native Swift, instant, polished pill), bilingual Swedish + English dictation, never lose a word (local-first recovery). No account, no word caps.

## Name and logo (owner feedback 2026-11-24)
First round (Swedish names Tyst / Ordna / Mumla, each with its own palette, serif or mascot) was rejected outright. Owner wants: an English name, a clean, very simple minimal monochrome mark, no mascot or chat bubble, no lime/neon, no serif in the app. The app keeps its clean SF Pro look. The only liked idea: sound-wave bars where the last bar becomes a text cursor.

Second round candidates (no dictation app found under these names, 2026-11-24): Caret, Typist (gettypist.com / usetypist.com free), Quiet (quiettype.app free). Taken by other dictation apps: Utter, Steno, Typeless, Viska, Sotto, Dikta.

MIT license requires keeping the original copyright notice; credit "based on SpeakType by Karan Singh" in About and README.

## Roadmap
1. Now: history freeze fix, faster dictation, settings declutter.
2. Weeks 2-3: rename, icon, colours, pill, own typography across the app.
3. Weeks 3-5: new site with demo video, Homebrew cask, signed download + auto-update, launch on HN / r/macapps / Product Hunt, comparison pages.
4. Months 2-3: dictionary, per-app styles, live text while speaking, voice-edit selection.
5. Later, optional: free + open forever; one-time supporter licence or paid hosted cleanup for people without a key.

## Decision (owner, 2026-11-25)
Mark: "caret" concept (three rounded sound bars ending in a thin text cursor), monochrome. Name: owner only wants "short, simple, easy to spell and remember in Swedish". Caret (caret.so, Mac AI typing app) and Typist (erusev.com, Mac dictation) are taken, so the app is **Taly** (sounds like Swedish "tala", not a Swedish word). Free domains: gettaly.com / usetaly.com (~$12/yr on Vercel; Cloudflare price unknown, no token). Runner-up: Tono (trytono.app). Not bought yet.

## Name change (owner, 2026-11-25)
Owner asked for a better name than Taly before release ("släpp. men bättre namn") and picked **Hum** from: Hum, Tono, Lilt, Saywell. No Mac dictation app found under these names (web search 2026-11-25). Taken or too close: Murmur (several), Harker, Spoke, Jot, Aloud (Mac dev feedback tool), Talkie. Taly was never released, so the update goes straight from SpeakType.app to Hum.app. Domain not bought yet.
