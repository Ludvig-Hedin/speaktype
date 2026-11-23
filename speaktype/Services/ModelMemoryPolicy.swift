import Foundation

/// Decides how the on-device Whisper model lives in memory.
///
/// **Owner intent (2026-11-23):** "use as little RAM as possible, both idle and while
/// transcribing." So the model is never preloaded at launch and never pinned in memory. It
/// loads when the hotkey is pressed (in parallel with the user speaking, so the load is mostly
/// hidden) and is released after a short idle window. Back-to-back dictations reuse it.
///
/// Cloud transcription never loads the local model at all.
enum ModelMemoryPolicy {
    /// Idle time before the model is released when the Mac has memory to spare. Long enough
    /// that a burst of dictations reuses one load, short enough that idle RAM returns quickly.
    static let idleUnloadDelay: TimeInterval = 120

    /// Idle time before release when free memory is tight.
    static let tightMemoryIdleUnloadDelay: TimeInterval = 30

    /// Estimated resident footprint of a loaded Core ML model, in gigabytes.
    ///
    /// WhisperKit's in-memory cost runs noticeably higher than the on-disk weights once the
    /// compute units, activations and tokenizer are loaded, so we scale the disk size up.
    static func estimatedFootprintGB(variant: String) -> Double {
        let diskBytes = AIModel.availableModels
            .first(where: { $0.variant == variant })?
            .expectedSizeBytes ?? 200_000_000
        return Double(diskBytes) / 1_073_741_824.0 * 1.8
    }

    /// Kept for callers that still ask; the model is never pinned resident any more.
    static func shouldKeepResident(variant: String) -> Bool { false }

    /// How long to wait before releasing the model, given current free memory.
    static func currentIdleUnloadDelay(variant: String) -> TimeInterval {
        let footprint = estimatedFootprintGB(variant: variant)
        let available = SystemMemory.availableMemoryGB()
        return available >= footprint * 2.0 + 1.5 ? idleUnloadDelay : tightMemoryIdleUnloadDelay
    }
}
