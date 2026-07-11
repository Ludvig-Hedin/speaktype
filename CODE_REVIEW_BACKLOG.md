# Code Review Backlog

## Bug Hunt — 2026-06-20 (round 5 — WaveformView, MenuBarDashboard, foregrounding; loop wind-down)

Final high-signal sweep. `xcodebuild -scheme speaktype -configuration Debug` → **BUILD SUCCEEDED**.

**Fixed (1):**

1. ✅ **WaveformView drew RANDOM data, not the actual recording** — `generateSamples()` filled the bars
   with `Float.random(...)` (an explicit "for now" placeholder), so the waveform had no relation to the
   audio and re-randomized every time the same history item was opened. Replaced with a real
   peak-amplitude downsample of the recording's first channel (read off the main thread via
   `AVAudioFile`, normalized 0...1, returns `[]` → draws nothing on any read failure).
   `WaveformView.swift`.

**Documented — NOT fixed (UX judgment on in-progress UI / out of bug-fix scope):**

- **Menu-bar hotkey picker offers "Custom…" with no way to record it there** — selecting `.custom`
  from `MenuBarDashboardView`'s compact picker when `CustomShortcutStorage.isSet == false` leaves the
  hotkey silently dead (`isKeyDownMatchingHotkey(.custom)` returns false), while the menu-bar icon
  still shows "enabled". The custom combo can only be recorded in Settings. Real foot-gun. Safe options:
  (a) hide `.custom` in the menu-bar picker unless already configured, or (b) route a `.custom`
  selection to open Settings/the recorder. Left for the user — it's a design decision on WIP UI.

**Verified clean:** menu-bar → dashboard foregrounding (`openDashboard` → `presentDashboardForeground()`
[`.regular` + activate] → `speaktype://open`) is intentional and matches shipped behavior;
`MenuBarDashboardView` stats now consistent post-delete (round-3 fix); `timeSavedMinutes` divides by a
literal (no div-by-zero); WaveformView has no timer/retain-cycle leak.

### Loop status — 5 rounds complete, 11 fixes, proposing stop

Across rounds 1-5: **11 real core-flow bugs fixed**, all build-verified, ~35 agent claims filtered as
false-positive/harmful. Remaining items are either deferred-by-design (WhisperService concurrency) or
UX-judgment calls on the user's in-progress UI (menu-bar Custom trap). No further clean, safe,
build-verifiable core-flow bugs found — recommending the loop stop here. Nothing committed (working
tree is user WIP); the user can review + commit `CODE_REVIEW_BACKLOG.md` + the touched files together.

---

## Bug Hunt — 2026-06-20 (round 4 — download cancel race, window lifecycle, WhisperService audit, audio playback)

Verified the round-2/3 leftover flags against real code. `xcodebuild -scheme speaktype
-configuration Debug` → **BUILD SUCCEEDED**.

**Fixed (3):**

1. ✅ **Download cancel → immediate re-download race** — `cancelDownload` reset `isDownloading=false`
   + `progress=0` *before* the async `deleteModel` cleanup ran, so a fast re-tap of Download passed
   the `isDownloading != true` guard and raced the in-flight delete (cleanup could wipe the new
   download's partial files → incomplete model). Now keeps `isDownloading=true` through cleanup;
   `deleteModel` clears it on completion, so the guard blocks re-tap until it's safe.
   `ModelDownloadService.cancelDownload`.
2. ✅ **Dead Play button in HistoryDetailView when audio file is missing** — the detail view rendered
   the player + Play button whenever `audioFileURL != nil`, with no existence check (HistoryView
   already gates on `audioFileExists`). Clicking Play did nothing. Now gates the section on
   `FileManager.fileExists`. `HistoryDetailView.swift:69`.
3. ✅ **`AudioPlayerService.loadAudio` left stale state on missing/failed file** — no existence check;
   on failure it logged and kept a stale player (duration/currentAudioURL out of sync). Now guards
   `fileExists` up front and `reset()`s on any failure — central robustness for all callers.

**Audited — DEFER (no safe minimal fix):**

- **WhisperService idle load/unload concurrency** — the races that could matter are already masked by
  design: `transcribe()` captures a strong-local `pipe` (survives a concurrent `unload()`),
  `loadModel` coalesces via `OSAllocatedUnfairLock` (no double-load), `unload()`/idle-unload
  self-guard on `isTranscribing`/`isLoading`/`isRecording` + a generation token. Residual
  unsynchronized `pipe`/`isInitialized` access is TSAN-flaggable but cannot drop/crash a real
  transcription (blast radius = reload latency). A partial lock-guard risks inconsistency with the
  existing lock; full actor isolation is architectural (touches every caller + the `Task.detached`
  warm-load). Left as-is — editing concurrency-sensitive WIP for a non-user-visible race is net-negative.

**Verified clean:** `MiniRecorderWindowController` (lazy panel, `weak self`, `isReleasedWhenClosed=false`,
no double-setup). The handleCommit focus/paste timing is the known round-2 limitation — risky to change
in WIP, still documented there.

---

## Bug Hunt — 2026-06-20 (round 3 — secondary flows: history/stats, audio device)

Traced history/stats + audio-device/settings flows via parallel investigators; verified every
claim against real code. `xcodebuild -scheme speaktype -configuration Debug` → **BUILD SUCCEEDED**.

**Fixed (2 areas, 4 edits):**

1. ✅ **History delete/clear left Statistics permanently wrong** — `deleteItem(at:)`, `deleteItem(id:)`
   and `clearAll()` mutated `items` + `saveHistory()` but never touched `statsEntries`/`saveStats()`.
   Statistics read from `statsEntries`, so a deleted (or fully cleared) transcript kept inflating
   word/duration totals forever, re-persisted across launches — also a mild privacy issue ("deleted"
   data lingering). Now mirror-deletes by id and saves stats. `HistoryService.swift:74-101`.
2. ✅ **Recording captured silence after the selected mic was unplugged** — `configureSession` left
   `captureSession = nil` when `selectedDeviceId` no longer resolved to a present device; the writer
   then ran with no samples → silent WAV → "No speech detected" on every recording until relaunch.
   Now falls back to `AVCaptureDevice.default(for: .audio)`. `AudioRecordingService.configureSession`.
3. ✅ **Selected mic not persisted across launches** — `selectedDeviceId` was in-memory only and reset
   to `availableDevices.first` every launch, contradicting the Settings copy ("used for all
   recordings"). Now persisted in `didSet` and restored in `fetchAvailableDevices` (only when still
   present; else first device). Redundant synchronous pick in `init` removed (it raced the restore).

**Verified NON-issues (do not re-flag):**

- **StatisticsView `components.year!`/`.month!` force-unwrap "crash on Year view"** — FALSE. Gregorian
  `dateComponents([.year,.month])` always yields non-nil for any real `Date`; divisions are guarded.
- **Settings "show menu bar icon" toggle not persisting** — FALSE. `@AppStorage("showMenuBarIcon")`
  persists; AppDelegate reads the same key with a `?? true` default. Consistent.

**Noted, lower priority (not fixed):**

- `AudioPlayerService.loadAudio` has no `fileExists` check → if a history item's audio was deleted/
  moved, the Play button silently no-ops (transcript text still intact). Degraded, not broken.
- After a mid-session unplug the UI still shows the unplugged device as "selected" (cosmetic; the
  default-device fallback means recording itself works). A stale-selection reset in
  `handleDeviceChange` would fix the checkmark.
- `ModelDownloadService` cancel-then-immediately-redownload was flagged in round 2 but not yet
  verified against real code — candidate for a future round.
- WhisperService idle-load/unload concurrency audit still outstanding (the dedicated agent hit a
  transient outage this round); recording path itself is guarded by `isStopping` + `audioQueue`.

---

## Bug Hunt — 2026-06-20 (round 2 — un-examined flows: onboarding/download, transcription/paste, update, license, Ollama polish)

Traced the flows NOT covered by the changed-files passes, via 4 parallel investigators, then
verified every claim against the real code (most agent findings were false positives or proposed
harmful fixes — recorded below so future passes don't re-chase them). `xcodebuild -scheme
speaktype -configuration Debug` → **BUILD SUCCEEDED**.

**Fixed (1):**

1. ✅ **Ollama polish 120s timeout froze the dictation→insert flow** — `OllamaPolishClient.polish`
   ran the inline polish request with `timeoutInterval = 120`. When Ollama is *up but slow/wedged*
   (model cold-loading, box thrashing) the recorder sat on "Polishing…" for up to 2 minutes,
   uncancellable, before the raw-text fallback kicked in. Reduced to **45s** — a healthy local
   polish on a small model answers in <10s even cold, so this bounds the worst case while still
   covering legitimate cold starts. (Server-down → connection-refused already fails instantly.)
   `OllamaPolishClient.swift:212`.

**Verified NON-issues (do not re-flag):**

- **Trial "1-day-early lockout"** — FALSE. `firstLaunch + 14d` end date is symmetric with `now`;
  the full 14×24h trial is honored. `TrialManager.checkTrialStatus`.
- **License `isPro = true` before async validation** — INTENTIONAL fail-open. Setting it false
  until validation would BLOCK a legitimate paying user who is offline at launch. Leave as-is.
  `LicenseManager.checkExistingLicense`.
- **UpdateSheet "trapped, cannot dismiss on error"** — FALSE. Install failure sets
  `isInstalling = false`, so Skip/Remind/Install buttons reappear; the window is also `.closable`.
- **Empty `finalText` commits empty string after polish** — FALSE. `WritingPolishService.polish`
  returns the raw transcript whenever the polished output is empty, so `finalText` is non-empty
  whenever the raw text is. Raw transcript is never lost on any polish failure path.
- **Empty `selectedModelVariant` → silent forever-lockout** — mitigated. The recorder guards on
  `selectedModel.isEmpty` and shows "No AI model selected. Go to Settings → AI Models", with a
  clear recovery; not a silent hang. `MiniRecorderView` start/process guards.
- **`ClipboardService.paste()` prints success on nil CGEvent / `documentDirectory.first!`** —
  cosmetic / effectively-never-nil on macOS; not worth a signature change or editing the
  concurrency-sensitive WhisperService. Skipped.

**Deferred follow-up (enhancement, not a regression):**

- Polish is still not *cancellable* mid-flight (Escape during "Polishing…" won't abort the inline
  Ollama call; it only bounds at 45s now). A proper fix races polish against a short deadline and
  inserts raw text immediately on timeout. Contained to the `MiniRecorderView` pipeline; left for
  a focused pass since it touches in-progress WIP.

---

## Bug Hunt — 2026-06-20 (FIXES APPLIED — hotkey core-flow breakers + mach leak)

Re-ran the changed-files bug hunt and fixed the high-confidence, build-verifiable issues
from the 2026-06-14 pass. `xcodebuild -scheme speaktype -configuration Debug` → **BUILD SUCCEEDED**.

**Fixed (4):**

1. ✅ **#1 Custom-combo hold mode stranded recording** — `AppDelegate.handleKeyUpEvent` now uses
   a new `isKeyUpMatchingHotkey` that matches the released hotkey by **keyCode only** (modifiers
   are intentionally ignored on the stop path, since they lift before the main key). The keyDown
   *start* path keeps the full modifier check. Recording now always stops on release.
2. ✅ **#2 Caps Lock hold mode broken** — Caps Lock is now driven as a pure toggle
   (`handleCapsLockToggle`): start when idle, stop when recording, regardless of recording mode.
   No longer relies on a release event that never arrives.
3. ✅ **#4 `SystemMemory` mach send-right leak** — added
   `defer { mach_port_deallocate(mach_task_self_, host) }` after `mach_host_self()`.
4. ✅ **#6 Custom shortcut stored polluted modifier mask** — record-time and match-time now both
   mask to `CustomShortcutStorage.relevantModifiers` (`[.control,.option,.shift,.command]`), so an
   incidental Caps Lock / Fn bit can no longer make a valid custom combo silently fail to fire.

**Still deferred (need runtime/TSAN verification — not fixable safely in this environment):**

- **#3 `WhisperService` shared mutable state across concurrency domains** — architectural; convert
  the model lifecycle to an `actor`/`@MainActor` or serial-queue guard. Practical blast radius is
  reload latency, not a crash. Left as-is.
- **#5 `AudioRecordingService.captureSession` read-on-main / write-on-`audioQueue` race** — low
  severity; ordering holds in practice. Route the nil-check through `audioQueue` when revisited.

---

## Bug Hunt — 2026-06-14 (changed files: background-mode + hotkey rework + idle model memory)

Scope: 9 modified + 4 new Swift files (AppDelegate, speaktypeApp, HotkeyOption,
AudioRecordingService, WhisperService, SelectedModelPreference, MenuBarDashboardView,
MiniRecorderView, SettingsView + new LaunchAtLoginService, ModelMemoryPolicy, SystemMemory,
ShortcutRecorderView).

No auto-fixes applied — every finding is either a concurrency/logic issue whose fix needs
runtime verification of global-hotkey behavior (not possible in this environment), or
architectural. TODO markers were added in `AppDelegate.swift` for the two confirmed logic bugs.

### Needs human review (6 issues)

1. **`AppDelegate.handleKeyUpEvent` — custom-combo hold mode strands recording** (logic, Medium)
   - `AppDelegate.swift` (`handleKeyUpEvent`, ~L315) — TODO marker added.
   - Repro: hotkey = Custom combo (e.g. ⌘+Space), mode = Hold (default). Press to start, then
     release ⌘ slightly before Space. Risk: `isKeyDownMatchingHotkey(.custom)` requires
     `eventModifiers == storedModifiers`; at Space's keyUp the modifier is already up, so
     match fails, `isPressed:false` never fires, `isHotkeyPressed` stays true → **recording
     never stops** until the hotkey is triggered again.
   - Suggested fix: for `.custom`, match keyUp on `keyCode` only; keep the modifier comparison
     on the keyDown (start) path. Validate by testing modifier-release-first and key-release-first.

2. **`AppDelegate.handleFlagsChangedEvent` — Caps Lock as a hold-mode hotkey is broken** (logic, Medium)
   - `AppDelegate.swift` (`handleFlagsChangedEvent` `.capsLock`, ~L274) — TODO marker added.
   - `.capsLock` reflects the LOCK toggle state, not a physical press. In Hold mode the first
     press latches Caps ON (start) and no release event arrives until the next tap → hold-to-talk
     never stops and inverts on subsequent uses. Caps Lock is offered in the Settings picker.
   - Suggested fix: treat Caps Lock as toggle-only, or remove it as an option.

3. **`WhisperService` — shared mutable state mutated across concurrency domains** (race, High-risk/architectural)
   - `WhisperService.swift` — `pipe`, `isInitialized`, `currentModelVariant`, `loadingTask`,
     `keepResident`, `idleUnloadGeneration` are read/written from MainActor views, a
     `Task.detached` warm-up (`MiniRecorderView.startRecording`), the internal `loadModel` task,
     and a `DispatchQueue.main.asyncAfter` idle-unload — with no synchronization. `WhisperService`
     is a plain `class`, not an `actor`/`@MainActor`.
   - Risk: data races on the load/unload state machine; TSAN-flaggable. Currently masked because
     `transcribe()` captures a strong local `pipe` and `unload()` self-guards on
     `isTranscribing`/`isLoading`, so the practical blast radius is extra reload latency, not a
     crash — but it is fragile.
   - Suggested fix: isolate the model lifecycle to an `actor` (or `@MainActor`), or guard the
     shared fields with a serial queue.

4. **`SystemMemory.availableMemoryGB` — `mach_host_self()` send-right not released** (resource leak, Low)
   - `SystemMemory.swift:21` — `mach_host_self()` returns a send right that should be balanced
     with `mach_port_deallocate(mach_task_self_, host)`. Called at launch and on each
     `shouldKeepResident` check → small, bounded port-ref leak.
   - Suggested fix: `defer { mach_port_deallocate(mach_task_self_, host) }` after acquiring `host`.

5. **`AudioRecordingService` — `captureSession` read on main, written on `audioQueue`** (race, Low)
   - `AudioRecordingService.swift` — `setupSession()` now configures the graph asynchronously on
     `audioQueue` (good for not blocking the UI), but callers still read `captureSession` on the
     main thread (`if captureSession == nil { setupSession() }` in `prewarmSession`/`startRecording`).
     The actual start is dispatched onto the same serial queue *after* the configure block, so
     ordering holds in practice; the unsynchronized property read/write is still a data race.
   - Suggested fix: route the `captureSession == nil` check through `audioQueue` too, or make the
     property access atomic.

6. **Custom shortcut stores the full `.deviceIndependentFlagsMask`** (edge logic, Low)
   - `ShortcutRecorderView.handleRecordingKeyDown` stores
     `modifiers = Int(maskedModifiers.rawValue)` using `.deviceIndependentFlagsMask`, which
     includes `.capsLock`, `.function`, `.numericPad`, `.help` — not just ⌃⌥⇧⌘. Matching in
     `AppDelegate.isKeyDownMatchingHotkey` masks the same way, so it is symmetric *unless* an
     incidental bit (e.g. Caps Lock state, or the `.function` bit on a laptop F-key) differs
     between record-time and press-time → the combo silently won't fire.
   - Suggested fix: when recording and when matching, mask to the four real modifiers only
     (`[.control, .option, .shift, .command]`), plus an explicit F-key allowance.

### Notes / non-issues checked
- `MiniRecorderView` uses `AudioRecordingService.shared`, so the idle-unload guard
  (`!AudioRecordingService.shared.isRecording`) covers the primary dictation path. Dashboard /
  TranscribeAudio use separate `AudioRecordingService()` instances, but `transcribe()` self-heals
  by reloading the model, so a mid-recording idle-unload only costs reload latency — not a failure.
- `loadModel` coalescing logic traced for same-variant and different-variant concurrent callers —
  correct (worst case is a redundant sequential reload, not corruption).
- Background-mode reachability invariant (never hide both Dock + menu-bar icon) is enforced in
  `applicationWillFinishLaunching`, the Settings `showDockIcon` onChange, and the disabled
  menu-bar-icon toggle. Consistent.
- `SMAppService.mainApp` requires macOS 13+; deployment target is 14.0 — OK.
