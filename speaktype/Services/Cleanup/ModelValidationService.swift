import Foundation

/// Startup validation: fetch each remote provider's live model list, mark which configured
/// model IDs resolve, log a summary, and repair the current selection if it no longer exists.
/// (Part 1 fallback rule + Part 3 "validate on startup, disable + warn on unresolved".)
enum ModelValidationService {
    /// CSV of catalog cleanup IDs that resolved against the live list. The picker disables the rest.
    static let resolvedCleanupIDsKey = "cleanupResolvedModelIDs"

    static var resolvedCleanupIDs: Set<String> {
        let csv = UserDefaults.standard.string(forKey: resolvedCleanupIDsKey) ?? ""
        return Set(csv.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    /// Print the STT engine inventory: which are usable now vs declared-but-not-yet-wired.
    static func logSTTInventory() {
        let live = STTEngineCatalog.implementedEngines.map(\.label)
        let planned = STTEngineCatalog.engines.filter { !$0.implemented }.map(\.label)
        print("✅ STT engines ACTIVE → \(live.joined(separator: ", "))")
        print("🧩 STT engines DECLARED (adapters planned) → \(planned.joined(separator: ", "))")
    }

    /// Fetch OpenRouter's live model IDs (public endpoint; key adds rate headroom).
    static func fetchOpenRouterModelIDs() async -> Set<String>? {
        guard let url = CleanupProvider.openRouter.modelsListURL else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if let key = RemoteAPIKeyStore.read(
            account: CleanupProvider.openRouter.keychainAccount,
            envVar: CleanupProvider.openRouter.envVar) {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = json["data"] as? [[String: Any]] else {
            return nil
        }
        return Set(array.compactMap { $0["id"] as? String })
    }

    /// Run at launch (off-main). Logs resolved/unresolved cleanup models and repairs the selection.
    static func validateOnStartup() async {
        logSTTInventory()
        guard let live = await fetchOpenRouterModelIDs() else {
            print("⚠️ ModelValidation: couldn't fetch OpenRouter models (offline/rate-limited); keeping configured selection.")
            return
        }

        var resolved: [String] = []
        var missing: [String] = []
        for model in CleanupModel.catalog where model.provider == .openRouter {
            if live.contains(model.id) { resolved.append(model.id) } else { missing.append(model.id) }
        }
        UserDefaults.standard.set(resolved.joined(separator: ","), forKey: resolvedCleanupIDsKey)

        print("✅ ModelValidation: cleanup models RESOLVED → \(resolved.isEmpty ? "(none)" : resolved.joined(separator: ", "))")
        if !missing.isEmpty {
            print("⚠️ ModelValidation: cleanup models UNRESOLVED (disabled, update the slug) → \(missing.joined(separator: ", "))")
        }

        // Repair the current selection if it no longer resolves.
        let current = UserDefaults.standard.string(forKey: WritingPolishUserDefaults.cleanupModelKey)
            ?? CleanupModel.defaultModelID
        guard !live.contains(current) else { return }

        let fallback: String? = live.contains(CleanupModel.defaultModelID)
            ? CleanupModel.defaultModelID
            : CleanupModel.firstResolved(Set(resolved))?.id
        if let fallback {
            UserDefaults.standard.set(fallback, forKey: WritingPolishUserDefaults.cleanupModelKey)
            print("⚠️ ModelValidation: selected cleanup model '\(current)' unavailable → fell back to '\(fallback)'.")
        } else {
            print("⚠️ ModelValidation: selected cleanup model '\(current)' unavailable and no resolved fallback found.")
        }
    }
}
