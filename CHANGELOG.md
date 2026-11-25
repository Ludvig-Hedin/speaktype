# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [Unreleased]
- **Web:** Free-only launch. Pricing shows one free plan with every feature and a note that Pro comes later; price rows and FAQ answers follow. Set `NEXT_PUBLIC_PAID_PLANS_OPEN=1` to show paid plans.

## [1.0.40] - 2026-11-25
- **App icon:** no grey frame around the icon on macOS 26.

## [1.0.39] - 2026-11-25
- **New name: Hum.** New minimal icon (four rounded bars). On update, SpeakType.app in Applications is renamed to Hum.app and keeps its place in the Dock.
- **History and Dashboard no longer freeze** when scrolling, and dictation waits less for cleanup.
- **Meeting recording:** a shortcut records you and the Mac's sound together, then transcribes the meeting.
- **Settings:** calmer layout, the OpenRouter key is asked for once, times read like "3h 28m".

## [1.0.38] - 2026-11-24
- **macOS, recorder:** Hovering the pill while you speak shows a grey X (cancel, same as Esc: nothing is pasted and the audio stays in History) and a white checkmark (finish and paste), like Wispr Flow. The language button is gone from the pill; pick the language in Settings. The pill now shows its own dark tooltips above it ("Cancel", "Finish and paste", what it is working on), because macOS never showed tooltips there.

## [1.0.37] - 2026-11-24
- **macOS:** The standard title bar supports native window dragging, tiling, double-click actions, and full screen.
- **Dictation:** Finished audio is saved locally before transcription. Escape stops insertion and keeps audio in History. If text is ready, the recorder offers Copy. Temporary cloud errors are retried when online and update the original History entry.
- **Updates:** SpeakType checks when it starts and while it runs in the background. Installation starts when you approve it. A manual check reports when you are up to date or when the check fails.

## [1.0.36] - 2026-11-24
- **macOS, recorder:** New small pill at the bottom center, like Wispr Flow: a live waveform while you speak, stop and language when you hover, soft dots while the text is written, and a checkmark once it is inserted. Errors are orange; notes stay neutral and wrap to two lines. Smooth fades and size changes; clicks around the pill pass through to the app below.
- **macOS, memory:** The on-device Whisper model is never preloaded and never pinned. It loads when you start dictating (while you speak) and is released after 2 minutes idle, or 30 seconds when memory is tight. Opening the dashboard or file view no longer loads it. Cloud transcription never loads it. Old unused audio chunk files are deleted.
- **macOS, local model:** New recommended model Whisper Large v3 Turbo Compact (632 MB): about a third of the memory of the full Turbo (~0.4 GB vs ~1.3 GB measured). Model compilation runs once, not on every load. Silent recordings are skipped as "No speech detected" (audio kept in History) instead of becoming "Thank you.", and local decoding skips silent stretches.
- **macOS, speed:** Cloud uploads are compressed (~8× smaller); GPT Transcribe answered in about 0.9 s instead of 2.5 s on the same clips. A model that rejects the compressed file gets the WAV.
- **macOS, cleanup:** Catalog refreshed: Claude Haiku 5.5 (default), DeepSeek V4.1 Flash, GPT-6 Luna, MiniMax M3.1 Flash, Gemini 3.5 Flash Lite. Retired models move to the default once. Reasoning is off for every cleanup model.
- **macOS, cloud transcription:** Added AssemblyAI Universal-3.6 Pro, ElevenLabs Scribe v2 and Voxtral Mini Transcribe 3. GPT Transcribe stays recommended.

## [1.0.35] - 2026-11-24
- **macOS:** GPT Transcribe can use a personal dictionary and a Swedish + English language hint. Claude Haiku 5.5 is the default for cloud text cleanup.
- **macOS:** Full Whisper Large v3 is available to download for on-device dictation.

## [1.0.34] - 2026-11-24
- **macOS, design:** Calmer, less cluttered app. Every screen is one centered column with a quieter title. Lists are one card with thin dividers instead of a box per item, and cards are flat (no shadows). Dashboard shows one row of stats with this week's bars; recent items keep Copy and Play quietly on the right. Settings is a single column with switches instead of checkboxes, and dropdowns no longer show two arrows. History rows open in place without jumping. Narrower sidebar. Fix: the Transcribe Audio screen no longer shows up blank.

## [1.0.32] - 2026-11-23
- **macOS:** Removed blue selection outlines. Focus rings appear during keyboard navigation and hide when you return to the mouse or trackpad.

## [1.0.31] - 2026-10-24
- **Web:** New marketing site in English and Swedish: home with an interactive dictation demo (pick a writing style), privacy, cleanup and customization sections, pricing (Free, Pro $6/mo or $48/yr, Lifetime $89), a Wispr Flow comparison page, and a restyled downloads page. Warm paper palette and Inter, after the 8pixel marketing site. Paid buttons use Polar checkout links from env and fall back to the free download until those exist. Adds sitemap, robots and hreflang.
- **macOS, reliability:** A failed transcription no longer deletes the recording. It is saved in History as "Transcription failed" with a Retry button. A quick tap during mic start-up now stops instead of recording on. Auto-paste restores the user's previous clipboard (never a password-manager copy) and marks its own write as transient. Without Accessibility the recorder says "Copied. Press ⌘V to paste." instead of failing silently. A new press replaces an on-screen message instead of being ignored. The mic no longer stays on after a start error. Escape only cancels while recording. The Fn hotkey works as soon as Accessibility is granted. History keeps line breaks from polished text. A press ignored during transcription can no longer change the paste target. Cloud transcription retries twice on timeouts, 429 and 5xx. Transcripts are no longer written to `/tmp/speaktype_debug.log`.
- **macOS, speed:** No fixed 0.5 s wait before pasting when the target app is already in front. The fixed 0.3 s mic warm-up sleep is replaced by waiting for the first audio buffer, which is kept, so first words are not clipped; 150 ms of audio is kept after release. Paste happens before History is saved, and saving runs off the main thread. Routing is computed once per recording.
- **macOS, menu bar:** "Paste Last Transcript". Dashboard Play button works. Empty states name the hotkey actually set. Local dictation stays unlimited after the trial.
- **Docs:** Wispr Flow research and the plan to win its users (`docs/strategy/`).

## [1.0.30] - 2026-08-30
- **Reliability:** Recording now starts only after microphone permission, capture, and the WAV writer are ready. Cloud-only ignores stale offline hints, shows the real provider error, and treats an empty successful STT response as no speech. Cancellation cannot save or paste late output. Ollama controls stay hidden for cloud cleanup. History cleanup removes audio files but keeps usage statistics.
- **macOS, release:** Release scripts use Apple Team `XDBG7P4V96` consistently.
- **macOS, recorder:** Duplicate stop signals are coalesced so only one audio finalization and transcription can run for a recording.
- **macOS, cloud transcription:** Cloud only no longer starts or falls back to a local Whisper model. The recorder closes immediately when cancelled, including during warm-up and transcription.
- **macOS, transcription:** OpenRouter can now transcribe with the same API key used for writing polish. The recommended model is `openai/gpt-transcribe`. The recorder no longer shows a stale Accessibility warning before every recording; paste still uses a live permission check.
- **Web (resilience):** `resolveLatestMacDownloadHref` wraps GitHub `releases/latest` fetch + JSON parse in try/catch with `console.error` and falls back to `LATEST_DMG_DOWNLOAD_URL`; non-OK responses log response body. `/downloads` wraps the resolver in try/catch so SSR never fails on API/network errors (`github-releases.ts`, `downloads/page.tsx`).
- **macOS — Ollama catalog:** Model selection compares whitespace-trimmed tags on both sides; after a successful `pullModel`, selection and pull UI clear immediately, and a separate refresh of `installedModelNames` can fail without undoing the pull (logs + optimistic `installedNames` append) (`OllamaRecommendedModelsView.swift`).
- **macOS — Writing polish:** Optional pass after Whisper via **Ollama** (`/api/chat`, `/api/pull` streaming) with default model **`qwen3.5:2b`** at `http://127.0.0.1:11434`. **Curated catalog** (Qwen 3.5 0.8B–9B, Ministral 3 · 3B, Nemotron 3 Nano 4B, Gemma 4 E2B/E4B): one-tap download + “Use” in **Settings** (`WritingPolishSettingsSection` + `OllamaRecommendedModelsView`) and **Onboarding** (`OnboardingPolishModelPage`). Presets, filler toggle, temperature, Ollama ping; raw transcript if unreachable/errors. Files: `OllamaPolishClient.swift`, `OllamaRecommendedModels.swift`, `WritingPolishService.swift`, `WritingPolishModels.swift`, `TranscriptionFinalizer.swift`, tests, `project.pbxproj` (removed `FoundationModels`).
- **Web:** Minimal Next.js site—hero, features, footer; **direct latest DMG** via `releases/latest/download`; **`/downloads`** lists all releases (API); benefit-led copy; larger, slower hero motion; env: `NEXT_PUBLIC_GITHUB_*`, optional `GITHUB_TOKEN`, `NEXT_PUBLIC_DMG_FILENAME` / `NEXT_PUBLIC_LATEST_DMG_URL`.
- **Release scripts:** `create-release.sh` writes `dist/SpeakType.dmg`; `deploy-release.sh` uploads **versioned DMG + `SpeakType.dmg`** for a stable `releases/latest/download/SpeakType.dmg` URL; `release.sh` uploads **only** the versioned notarized DMG (no duplicate identical asset). The site resolves the latest `.dmg` via the GitHub API when no `NEXT_PUBLIC_LATEST_DMG_URL` is set (`RELEASE.md` updated).
- **Updates (macOS):** `GitHubUpdatesRepository` in Info.plist + `UpdateConfiguration`; checks use your repo; silent launch checks show the update window on the reminder schedule; single update window de-dupe; GitHub release `body` optional in JSON; Settings → “Browse all releases…” opens GitHub.
- **Polish:** Mini recorder panel comment matches 300pt width; `Color.appGraphite` replaces misleading `appRed` (deprecated alias); pointer cursor modifiers balance `NSCursor` on disable/disappear (click-action modifier, onboarding buttons, sidebar rows); settings device list shows **Active** only while recording on the selected input (`SettingsView`, `AudioInputView`).
- **UX (macOS):** Pointing-hand cursor on interactive controls — `ClickActionPointerCursorModifier` / `.clickActionPointerCursor()`, wired through `STPlainButtonStyle` and primary/secondary/ghost styles; applied to menus, toggle rows, device rows, update sheet checkbox, and the transcribe drop zone (`View+Extensions.swift`, `ColorSystem.swift`, settings/mini-recorder/update/transcribe views).
- **Settings:** Single scrollable screen — General, Audio, and Permissions are stacked in one view (tab bar removed) (`SettingsView.swift`).
- **UI refresh (macOS):** Neutral grayscale system replaces lavender/purple selection tints; cards and settings use **liquid-glass** stacks (`.ultraThinMaterial` + neutral tint + soft strokes). Controls are **pill-shaped** with clearer active states (custom recording-mode picker, tab chips, radios). Typography tightened via `.stCompactUI()` on key settings copy. Touches: ColorSystem, Constants, Theme, Sidebar, Settings, Dashboard, AIModels, ModelRow, AudioInputView, MiniRecorderView, Onboarding, ProFeatureGate, AmbientBackground, View+Extensions, Typography, AppColors.
- **Mini recorder:** The floating bar’s red control now reliably stops recording in toggle mode (uses `AudioRecordingService.isRecording`, not only local SwiftUI state), shows a clear **Stop** label, and uses a proper button + tooltip. Panel width adjusted to fit the label (MiniRecorderView, MiniRecorderWindowController).
- **Onboarding / models:** New step downloads the RAM-recommended Whisper model before finishing setup; default selection stays in sync with on-disk models so the hotkey flow no longer shows “No model selected” when files already exist. Startup preloads WhisperKit after a disk scan for faster first transcription (SelectedModelPreference, ModelDownloadService, AppDelegate, OnboardingView, MiniRecorderView, AIModelsView, DashboardView).

## [1.0.29] - 2026-03-24
- **Distribution:** GitHub release [v1.0.29](https://github.com/Ludvig-Hedin/speaktype/releases/tag/v1.0.29) includes `SpeakType.dmg` built locally (**not Apple-notarized** — Gatekeeper may prompt). This was a temporary exception; releases produced with `scripts/release.sh` are Developer ID–signed, **notarized**, and stapled before upload, and future tagged releases are intended to follow that path.

## [1.0.28] - 2026-03-22
- 

## [1.0.27] - 2026-03-22
- 

## [1.0.25] - 2026-03-21
- 

## [1.0.24] - 2026-03-12
- 

## [1.0.23] - 2026-02-27
- 

## [1.0.22] - 2026-02-27
- 

## [1.0.21] - 2026-02-17
- 

## [1.0.20] - 2026-02-17
- 

## [1.0.19] - 2026-02-16
- 

## [1.0.18] - 2026-02-16
- 

## [1.0.17] - 2026-02-16
- 

## [1.0.16] - 2026-02-15
- 

## [1.0.15] - 2026-02-15
- 

## [1.0.14] - 2026-02-15
- 

## [1.0.13] - 2026-02-15
- 

## [1.0.12] - 2026-02-15
- 

## [1.0.11] - 2026-02-15
- 

## [1.0.10] - 2026-02-14
- 

## [1.0.7] - 2026-02-03
- 

## [1.0.6] - 2026-02-03
- 

## [1.0.5] - 2026-01-27
- 
