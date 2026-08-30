import Foundation

/// Pure, testable decision logic: given the current mode + machine state, produce an ordered
/// chain of providers to try (first = preferred, rest = fallbacks). Kept free of side effects
/// so it can be unit-tested like `SelectedModelPreference.resolveSelection`.
enum TranscriptionRouter {
    struct Inputs {
        let mode: TranscriptionMode
        let localAvailable: Bool          // selected Whisper model downloaded
        let remoteProvider: TranscriptionProviderKind?  // configured provider kind, if any
        let remoteConfigured: Bool        // key present + consent given + model resolved
        let networkAvailable: Bool
        let availableRAMGB: Double
        let localFootprintGB: Double      // ModelMemoryPolicy.estimatedFootprintGB(localVariant)
        let cpuLoadPerCore: Double
    }

    static func resolveChain(_ i: Inputs) -> [TranscriptionProviderKind] {
        let local: [TranscriptionProviderKind] = i.localAvailable ? [.localWhisper] : []
        let configuredRemote: [TranscriptionProviderKind]
        if let provider = i.remoteProvider, i.remoteConfigured {
            configuredRemote = [provider]
        } else {
            configuredRemote = []
        }
        let reachableRemote = i.networkAvailable ? configuredRemote : []

        switch i.mode {
        case .localOnly:
            return local

        case .remoteOnly:
            // Reachability can briefly report offline while the network is usable. In an
            // explicit cloud-only mode, attempt the request and surface its real error.
            return configuredRemote

        case .auto:
            // Keep it local when the Mac can comfortably do it; otherwise offload.
            // RAM term reuses ModelMemoryPolicy's residency math so `auto` agrees with it.
            let localComfortable =
                i.localAvailable &&
                i.availableRAMGB >= i.localFootprintGB * 2.0 + 1.5 &&
                i.cpuLoadPerCore < 0.85
            return localComfortable ? local + reachableRemote : reachableRemote + local
        }
    }
}
