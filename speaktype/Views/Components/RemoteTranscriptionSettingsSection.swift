import AppKit
import SwiftUI

/// Settings card for choosing on-device vs cloud transcription, entering a provider API key
/// (stored in the Keychain), and consenting to audio upload. Mirrors the layout language of
/// `WritingPolishSettingsSection` + the shared `SettingsSection`/`RadioButton` components.
struct RemoteTranscriptionSettingsSection: View {
    @AppStorage(TranscriptionModeUserDefaults.modeKey) private var modeRaw = TranscriptionMode.localOnly.rawValue
    @AppStorage(TranscriptionModeUserDefaults.remoteProviderKey) private var providerRaw = ""
    @AppStorage(TranscriptionModeUserDefaults.remoteModelKey) private var modelId = ""
    @AppStorage(TranscriptionModeUserDefaults.consentKey) private var consent = false

    @State private var apiKeyInput = ""
    @State private var keySaved = false
    @State private var statusMessage = ""

    private var mode: TranscriptionMode { TranscriptionMode(rawValue: modeRaw) ?? .localOnly }
    private var provider: RemoteProvider? { RemoteProvider(rawValue: providerRaw) }

    var body: some View {
        SettingsSection {
            SettingsSectionHeader(
                icon: "cloud",
                title: "Transcription engine",
                subtitle: "Choose on-device, cloud, or automatic")

            VStack(alignment: .leading, spacing: 16) {
                modePicker

                Text(mode.explanation)
                    .font(Typography.captionSmall)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if mode.canUseRemote {
                    Divider().overlay(Color.border.opacity(0.4))
                    providerPicker
                    if provider != nil {
                        modelPicker
                        apiKeyField
                        consentToggle
                    }
                    privacyNote
                }
            }
        }
        .onAppear(perform: refreshKeyState)
    }

    // MARK: - Mode

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(TranscriptionMode.allCases) { option in
                RadioButton(
                    title: option.displayName,
                    isSelected: mode == option,
                    action: { modeRaw = option.rawValue }
                )
            }
            Spacer()
        }
    }

    // MARK: - Provider

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cloud provider")
                .font(Typography.labelMedium)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 8) {
                ForEach(RemoteProvider.allCases) { p in
                    RadioButton(
                        title: p.displayName,
                        isSelected: provider == p,
                        action: { selectProvider(p) }
                    )
                }
                Spacer()
            }
        }
    }

    private var modelPicker: some View {
        HStack {
            Text("Model")
                .font(Typography.bodyMedium)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Picker("", selection: Binding(
                get: { resolvedModelId },
                set: { modelId = $0 }
            )) {
                if let provider {
                    ForEach(RemoteTranscriptionModel.models(for: provider)) { m in
                        Text(m.name).tag(m.id)
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
        }
    }

    private var resolvedModelId: String {
        guard let provider else { return "" }
        if let m = RemoteTranscriptionModel.model(id: modelId), m.provider == provider { return m.id }
        return RemoteTranscriptionModel.defaultModel(for: provider)?.id ?? ""
    }

    // MARK: - API key

    private var apiKeyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API key")
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let provider {
                    Button("Get a key ↗") {
                        if let url = URL(string: provider.apiKeyURL) { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.link)
                    .font(Typography.captionSmall)
                }
            }

            if keySaved {
                HStack(spacing: 10) {
                    Label("Key saved", systemImage: "checkmark.seal.fill")
                        .font(Typography.captionSmall)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Replace") { keySaved = false; apiKeyInput = "" }
                        .buttonStyle(.link)
                        .font(Typography.captionSmall)
                    Button("Remove", role: .destructive) { removeKey() }
                        .buttonStyle(.link)
                        .font(Typography.captionSmall)
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("sk-…", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") { saveKey() }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || provider == nil)
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(Typography.captionSmall)
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private var consentToggle: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $consent).labelsHidden()
            Text("I understand my audio is uploaded to \(provider?.displayName ?? "the provider") for transcription.")
                .font(Typography.captionSmall)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyNote: some View {
        Text("Cloud transcription sends your recorded audio off your Mac. Keys are stored in the macOS Keychain and never leave your device except as the Authorization header for the request. Cloud is only used after you add a key and give consent above.")
            .font(Typography.captionSmall)
            .foregroundStyle(Color.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private func selectProvider(_ p: RemoteProvider) {
        providerRaw = p.rawValue
        modelId = RemoteTranscriptionModel.defaultModel(for: p)?.id ?? ""
        refreshKeyState()
    }

    private func refreshKeyState() {
        keySaved = provider.map { RemoteAPIKeyStore.hasKey(for: $0) } ?? false
    }

    private func saveKey() {
        guard let provider else { return }
        if RemoteAPIKeyStore.save(apiKeyInput, for: provider) {
            apiKeyInput = ""
            keySaved = true
            statusMessage = "Saved to Keychain."
        } else {
            statusMessage = "Couldn't save the key."
        }
    }

    private func removeKey() {
        guard let provider else { return }
        RemoteAPIKeyStore.delete(for: provider)
        keySaved = false
        apiKeyInput = ""
        statusMessage = "Key removed."
    }
}
