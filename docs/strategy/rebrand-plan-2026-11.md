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

## Name directions (owner to pick)
| Name | Feel | Free domain found | Note |
|---|---|---|---|
| Tyst | calm, dark, precise | gettyst.com | hard to pronounce for non-Swedes |
| Ordna | warm, editorial | useordna.com | "ord" + "ordna": messy speech becomes tidy text |
| Mumla | playful, bold | getmumla.com | easiest internationally |

Rejected because other dictation apps use them: Viska, Sotto, Dikta. Short .app/.com domains for all three are registered.

MIT license requires keeping the original copyright notice; credit "based on SpeakType by Karan Singh" in About and README.

## Roadmap
1. Now: history freeze fix, faster dictation, settings declutter.
2. Weeks 2-3: rename, icon, colours, pill, own typography across the app.
3. Weeks 3-5: new site with demo video, Homebrew cask, signed download + auto-update, launch on HN / r/macapps / Product Hunt, comparison pages.
4. Months 2-3: dictionary, per-app styles, live text while speaking, voice-edit selection.
5. Later, optional: free + open forever; one-time supporter licence or paid hosted cleanup for people without a key.
