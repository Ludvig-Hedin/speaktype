# SpeakType — agent memory

## Transcription pipeline

1. **WhisperKit** (on-device Core ML) produces raw text; `WhisperService.normalizedTranscription` strips noise tokens.
2. **Writing polish** (optional): `TranscriptionFinalizer.finalizeTranscript` calls `WritingPolishService.polish` when `writingPolishEnabled` is on. It POSTs to **Ollama** `/api/chat` (default `http://127.0.0.1:11434`, default model **`qwen3.5:2b`**) with system instructions from the user’s preset. Model install: `OllamaPolishClient.pullModel` streams `/api/pull` for progress. On connection/model errors, **output is the raw transcript** (never block paste/history).

## Curated Ollama models (polish)

Defined in `OllamaRecommendedModels.swift` / UI in `OllamaRecommendedModelsView`: `qwen3.5:0.8b`, `qwen3.5:2b` (recommended default), `nemotron-3-nano:4b`, `ministral-3:3b`, `qwen3.5:9b`, `gemma4:e2b`, `gemma4:e4b` — ordered small → large with size labels and RAM hints.

## User defaults keys

- `writingPolishEnabled` (default `true` via `registerDefaults`)
- `writingPolishPreset` (raw `WritingPolishPreset`)
- `writingPolishRemoveFillers` (default `true`)
- `writingPolishOllamaBaseURL` (default `http://127.0.0.1:11434`)
- `writingPolishOllamaModel` (default `qwen3.5:2b`)
- `writingPolishOllamaTemperature` (default `0.2`)

## UI

- **Settings:** `WritingPolishSettingsSection` — Ollama URL, ping, **`OllamaRecommendedModelsView`** (pull + use), optional custom tag field, temperature, preset.
- **Onboarding:** `OnboardingPolishModelPage` — same catalog + enable toggle before Whisper model step.

## Releases & website downloads

- **`scripts/release.sh`:** Developer ID build, notarized + stapled DMG; `gh release create` attaches **one** versioned artifact (no duplicate `SpeakType.dmg` copy). Stable named asset `SpeakType.dmg` on the same tag: use **`scripts/deploy-release.sh`** (syncs `dist/SpeakType.dmg` from the built DMG every run) or set `NEXT_PUBLIC_LATEST_DMG_URL`.
- **Marketing site:** `resolveLatestMacDownloadHref()` (`github-releases.ts`) uses `NEXT_PUBLIC_LATEST_DMG_URL` if set, else the **latest** GitHub release’s first `.dmg`, else falls back to `releases/latest/download/{DMG_ASSET_NAME}`. Fetch/parse errors log with `console.error` and use the same static fallback; `/downloads` also try/catches the resolver so SSR survives API failures.
- **`OllamaPolishClient.pullModel`:** If the pull stream ends without a `success` status, throws `ClientError.pullStreamIncomplete` (no fake “Finished.” at 1.0).
