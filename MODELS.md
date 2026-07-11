# Model Registry

Config-driven registry for cleanup (LLM) + STT models. Adding a model = **one entry**, no
control-flow changes. Source-of-truth is Swift (validated + type-checked); this file documents
the shape (mirrors the Part 3 spec).

## Providers

| provider   | base_url                          | key (env → Keychain)          | default |
|------------|-----------------------------------|-------------------------------|---------|
| openrouter | `https://openrouter.ai/api/v1`    | `OPENROUTER_API_KEY` / `openrouter_api_key` | ✅ cleanup default |
| openai     | `https://api.openai.com/v1`       | `OPENAI_API_KEY` / `openai_api_key`         | secondary |
| groq       | `https://api.groq.com/openai`     | `GROQ_API_KEY` / `groq_api_key`             | STT cloud |
| local      | on-device (WhisperKit / Ollama)   | — (no key)                                  | STT + cleanup local |

Keys resolve **env var → Keychain** (`RemoteAPIKeyStore`). Never hardcoded. GUI users enter keys
in Settings (Keychain); env vars are a dev convenience for shell-launched runs.

## Cleanup models — `CleanupModel.catalog`

Default: `google/gemini-flash-latest` (auto-tracks current Gemini flash). All via OpenRouter,
OpenAI-compatible `/chat/completions`, **temperature 0**, verbatim cleanup system prompt,
per-request `provider.data_collection = "deny"` (no-train).

On startup `ModelValidationService.validateOnStartup()` fetches the live `/models` list, marks
each catalog ID resolved/unresolved (unresolved → shown "(unavailable)" and disabled), and repairs
the selection: missing default → first resolved in catalog order.

To add a cleanup model: append a `CleanupModel(id:provider:label:note:)` to the catalog.

## STT engines — `STTEngineCatalog.engines`

Each entry: `id, label, provider, modelID, kind(local|cloud), streaming, languages,
supportsSwedish, swedishFallbackEngineID, implemented, experimental, note`.

**Active now** (`implemented: true`, wired through `TranscriptionProvider`): on-device Whisper,
OpenAI Transcribe, Groq Whisper Large v3 Turbo.

**Declared, adapters planned** (`implemented: false`, not offered in UI until wired):
Parakeet-TDT-0.6B-v3 (preferred local default — needs NeMo/CoreML runtime), MAI-Transcribe-1,
AssemblyAI Universal-3 Pro (+ Universal-2 sv fallback), Deepgram Nova-3/Flux,
OpenAI GPT-Realtime-Whisper, ElevenLabs Scribe v2 Realtime, Whisper Turbo live + Silero VAD,
Speechmatics Ursa 2, Voxtral Realtime (experimental).

**Swedish auto-routing:** `STTEngineCatalog.resolve(engineID:language:)` — when language is `sv*`
and the engine lacks Swedish (AssemblyAI Universal-3 Pro), it returns the declared
`swedishFallbackEngineID` (Universal-2) and logs the switch.

To add an STT engine: append an `STTEngine(...)` entry. Set `implemented: true` only once its
adapter conforms to `TranscriptionProvider`.

## RAM-based local→cloud fallback

`WritingPolishService.effectiveProvider` switches a **local** cleanup to a configured cloud
provider when free RAM < `cleanupLocalRAMThresholdGB` (default 6 GB, settable). STT `auto` mode
does the equivalent via `TranscriptionRouter`.
