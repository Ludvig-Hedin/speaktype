# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [Unreleased]
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
