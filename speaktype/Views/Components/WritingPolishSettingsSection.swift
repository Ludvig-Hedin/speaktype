import AppKit
import SwiftUI

/// Shared writing-polish controls for Settings and Onboarding (same `UserDefaults` keys).
struct WritingPolishSettingsSection: View {
    var compact: Bool = false

    @AppStorage("writingPolishEnabled") private var writingPolishEnabled = true
    @AppStorage("writingPolishPreset") private var writingPolishPresetRaw = WritingPolishPreset.clean.rawValue
    @AppStorage("writingPolishRemoveFillers") private var writingPolishRemoveFillers = true
    @AppStorage(WritingPolishUserDefaults.ollamaBaseURLKey) private var ollamaBaseURL =
        WritingPolishUserDefaults.defaultOllamaBaseURL
    @AppStorage(WritingPolishUserDefaults.ollamaModelKey) private var ollamaModel =
        WritingPolishUserDefaults.defaultOllamaModel
    @AppStorage(WritingPolishUserDefaults.ollamaTemperatureKey) private var ollamaTemperature = 0.2

    @State private var ollamaPingResult: String?
    @State private var isPingingOllama = false

    @AppStorage(WritingPolishUserDefaults.cleanupProviderKey) private var cleanupProviderRaw =
        WritingPolishUserDefaults.defaultCleanupProvider
    @AppStorage(WritingPolishUserDefaults.cleanupModelKey) private var cleanupModelID =
        WritingPolishUserDefaults.defaultCleanupModel
    @State private var cleanupKeyInput = ""
    @State private var cleanupKeySaved = false
    @State private var cleanupKeyStatus = ""

    private var cleanupProvider: CleanupProvider {
        CleanupProvider(rawValue: cleanupProviderRaw) ?? .openRouter
    }

    private var selectedPreset: WritingPolishPreset {
        WritingPolishPreset(rawValue: writingPolishPresetRaw) ?? .clean
    }

    private func refreshCleanupKey() {
        cleanupKeySaved = cleanupProvider.isRemote
            ? RemoteAPIKeyStore.hasKey(account: cleanupProvider.keychainAccount, envVar: cleanupProvider.envVar)
            : true
    }

    private func saveCleanupKey() {
        if RemoteAPIKeyStore.save(cleanupKeyInput, account: cleanupProvider.keychainAccount) {
            cleanupKeyInput = ""
            cleanupKeySaved = true
            cleanupKeyStatus = "Saved to Keychain."
        } else {
            cleanupKeyStatus = "Couldn't save the key."
        }
    }

    private func removeCleanupKey() {
        RemoteAPIKeyStore.delete(account: cleanupProvider.keychainAccount)
        cleanupKeySaved = false
        cleanupKeyInput = ""
        cleanupKeyStatus = "Key removed."
    }

    private func cleanupModelLabel(_ m: CleanupModel) -> String {
        let resolved = ModelValidationService.resolvedCleanupIDs
        if !resolved.isEmpty, !resolved.contains(m.id) { return m.label + " (unavailable)" }
        return m.label
    }

    @ViewBuilder private var cleanupKeyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(cleanupProvider.displayName) API key")
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let urlStr = cleanupProvider.apiKeyURL {
                    Button("Get a key ↗") {
                        if let url = URL(string: urlStr) { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.link)
                    .font(Typography.captionSmall)
                }
            }

            if cleanupKeySaved {
                HStack(spacing: 10) {
                    Label("Key saved", systemImage: "checkmark.seal.fill")
                        .font(Typography.captionSmall)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Replace") { cleanupKeySaved = false; cleanupKeyInput = "" }
                        .buttonStyle(.link).font(Typography.captionSmall)
                    Button("Remove", role: .destructive) { removeCleanupKey() }
                        .buttonStyle(.link).font(Typography.captionSmall)
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("sk-…" + (cleanupProvider.envVar.map { "  (or $\($0))" } ?? ""), text: $cleanupKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") { saveCleanupKey() }
                        .disabled(cleanupKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if !cleanupKeyStatus.isEmpty {
                Text(cleanupKeyStatus)
                    .font(Typography.captionSmall)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private var configSummary: String {
        let c = WritingPolishConfiguration(
            isEnabled: writingPolishEnabled,
            preset: selectedPreset,
            removeFillers: writingPolishRemoveFillers,
            ollamaBaseURL: ollamaBaseURL,
            ollamaModel: ollamaModel,
            ollamaTemperature: ollamaTemperature
        )
        return WritingPolishService.configurationSummary(config: c)
    }

    var body: some View {
        SettingsSection {
            SettingsSectionHeader(
                icon: "text.quote",
                title: "Writing polish",
                subtitle: compact
                    ? "Optional pass after transcription (Ollama)"
                    : "Turn speech into clearer writing with a small local LLM via Ollama"
            )

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Polish speech into clear writing")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Toggle("", isOn: $writingPolishEnabled)
                        .labelsHidden()
                }
                .clickActionPointerCursor()

                Text(configSummary)
                    .font(Typography.captionSmall)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                // Cleanup engine (Part 1): OpenRouter (default) / OpenAI / Local Ollama.
                Divider().overlay(Color.border.opacity(0.4))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Cleanup engine")
                        .font(Typography.labelMedium)
                        .foregroundStyle(Color.textSecondary)
                    HStack(spacing: 8) {
                        ForEach(CleanupProvider.allCases) { p in
                            RadioButton(
                                title: p.displayName,
                                isSelected: cleanupProvider == p,
                                action: { cleanupProviderRaw = p.rawValue; refreshCleanupKey() }
                            )
                        }
                        Spacer()
                    }

                    if cleanupProvider.isRemote {
                        HStack {
                            Text("Cleanup model")
                                .font(Typography.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Picker("", selection: $cleanupModelID) {
                                ForEach(CleanupModel.catalog) { m in
                                    Text(cleanupModelLabel(m)).tag(m.id)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 260)
                        }

                        cleanupKeyField

                        Text("Runs at temperature 0 with a strict cleanup prompt — preserves English/Swedish, never answers the dictation. OpenRouter requests send a no-train (data_collection: deny) policy.")
                            .font(Typography.captionSmall)
                            .foregroundStyle(Color.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Local cleanup uses your Ollama settings below. It also serves as the offline fallback when a cloud engine is unreachable.")
                            .font(Typography.captionSmall)
                            .foregroundStyle(Color.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(!writingPolishEnabled)
                .onAppear(perform: refreshCleanupKey)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ollama base URL")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    TextField("http://127.0.0.1:11434", text: $ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(Typography.bodySmall)
                        .disabled(!writingPolishEnabled)
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await runOllamaPing() }
                    } label: {
                        HStack(spacing: 6) {
                            if isPingingOllama {
                                ProgressView()
                                    .scaleEffect(0.65)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 12))
                            }
                            Text(isPingingOllama ? "Checking…" : "Check Ollama")
                                .font(Typography.labelMedium)
                        }
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.border.opacity(0.45), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.stPlain)
                    .disabled(isPingingOllama || !writingPolishEnabled)

                    Spacer()
                }

                if let ping = ollamaPingResult {
                    Text(ping)
                        .font(Typography.captionSmall)
                        .foregroundStyle(
                            ping.hasPrefix("OK") ? Color.accentSuccess.opacity(0.9) : Color.textSecondary
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }

                OllamaRecommendedModelsView(
                    ollamaBaseURL: $ollamaBaseURL,
                    selectedModelTag: $ollamaModel,
                    layout: .settings
                )
                .disabled(!writingPolishEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom model (optional)")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    TextField(WritingPolishUserDefaults.defaultOllamaModel, text: $ollamaModel)
                        .textFieldStyle(.roundedBorder)
                        .font(Typography.bodySmall)
                        .disabled(!writingPolishEnabled)
                    Text("Override the catalog with any tag Ollama knows, e.g. llama3.2:3b.")
                        .font(Typography.captionSmall)
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature")
                            .font(Typography.bodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(String(format: "%.2f", ollamaTemperature))
                            .font(Typography.captionSmall)
                            .foregroundStyle(Color.textMuted)
                    }
                    Slider(value: $ollamaTemperature, in: 0 ... 1, step: 0.05)
                        .disabled(!writingPolishEnabled)
                    Text("Lower = stick closer to your words; slightly higher can read smoother.")
                        .font(Typography.captionSmall)
                        .foregroundStyle(Color.textMuted)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Style preset")
                            .font(Typography.bodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Menu {
                            ForEach(WritingPolishPreset.allCases) { preset in
                                Button {
                                    writingPolishPresetRaw = preset.rawValue
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.displayName)
                                        Text(preset.menuDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedPreset.displayName)
                                    .font(Typography.bodySmall)
                                    .foregroundStyle(Color.textPrimary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.textMuted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.thinMaterial, in: Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.border.opacity(0.45), lineWidth: 0.5)
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .clickActionPointerCursor()
                        .disabled(!writingPolishEnabled)
                    }

                    Text(selectedPreset.menuDescription)
                        .font(Typography.captionSmall)
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text("Remove filler words (um, uh, …)")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Toggle("", isOn: $writingPolishRemoveFillers)
                        .labelsHidden()
                        .disabled(!writingPolishEnabled)
                }
                .clickActionPointerCursor()

                Text(
                    "Whisper runs on your Mac. Polish calls your Ollama server (usually localhost), not SpeakType’s servers. If Ollama is down or the model is missing, you still get the raw transcript."
                )
                .font(Typography.captionSmall)
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .stCompactUI()
            }
        }
        .onAppear {
            Task { await runOllamaPing() }
        }
    }

    private func runOllamaPing() async {
        guard writingPolishEnabled else {
            await MainActor.run { ollamaPingResult = nil }
            return
        }
        await MainActor.run {
            isPingingOllama = true
            ollamaPingResult = nil
        }
        do {
            try await OllamaPolishClient.ping(baseURLString: ollamaBaseURL)
            await MainActor.run {
                ollamaPingResult = "OK — Ollama is reachable."
                isPingingOllama = false
            }
        } catch {
            await MainActor.run {
                ollamaPingResult =
                    "Could not reach Ollama. \(error.localizedDescription)"
                isPingingOllama = false
            }
        }
    }
}
