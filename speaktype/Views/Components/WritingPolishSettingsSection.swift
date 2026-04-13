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

    private var selectedPreset: WritingPolishPreset {
        WritingPolishPreset(rawValue: writingPolishPresetRaw) ?? .clean
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
                            ping.hasPrefix("OK") ? Color.green.opacity(0.9) : Color.textSecondary
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
