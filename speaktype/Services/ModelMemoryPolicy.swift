import Foundation

/// Decides how the Whisper model should live in memory, based on the Mac's free RAM.
///
/// **User intent:** "If I have lots of free RAM, preload the model and keep it ready.
/// If I'm low on RAM, don't preload — load it only when I dictate and release it when idle."
///
/// So the policy has two outcomes:
/// - **Keep resident** (ample RAM): preload at launch, never auto-release. Fastest dictation.
/// - **Lazy + idle-unload** (tight RAM): skip launch preload, load on the first hotkey press,
///   and release the model after a short idle window to give RAM back to the system.
enum ModelMemoryPolicy {
    /// How long the model may sit unused before it is released (lazy mode only).
    static let idleUnloadDelay: TimeInterval = 180  // 3 minutes

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

    /// `true` when there is comfortable headroom to keep the model loaded all the time.
    ///
    /// Requires free RAM ≥ (2 × model footprint) + 1.5 GB OS/app buffer. The 2× leaves room
    /// for the transient spike while a transcription runs without pushing the system into
    /// memory pressure. When in doubt (Mach call failed → 0 GB free), returns `false` so we
    /// fall back to the safe, low-memory lazy path.
    static func shouldKeepResident(variant: String) -> Bool {
        guard !variant.isEmpty else { return false }
        let footprint = estimatedFootprintGB(variant: variant)
        let available = SystemMemory.availableMemoryGB()
        return available >= footprint * 2.0 + 1.5
    }
}
