import AppKit
import SwiftUI

/// One-tap **pull** + **use** for curated polish models (Settings + Onboarding).
struct OllamaRecommendedModelsView: View {
    @Binding var ollamaBaseURL: String
    @Binding var selectedModelTag: String

    enum LayoutStyle {
        case onboarding
        case settings
    }

    var layout: LayoutStyle = .settings

    @State private var installedNames: [String] = []
    @State private var ollamaReachable = false
    @State private var isRefreshing = false
    @State private var pullingTag: String?
    @State private var pullFraction: Double?
    @State private var pullStatus: String = ""
    @State private var bannerError: String?

    private var deviceRAMGB: Int { WhisperService.deviceRAMGB }

    var body: some View {
        VStack(alignment: .leading, spacing: layout == .onboarding ? 14 : 12) {
            if !ollamaReachable {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Install Ollama, then come back — one click downloads the polish model.")
                        .font(layout == .onboarding ? .system(size: 14) : Typography.bodySmall)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button {
                            if let url = URL(string: "https://ollama.com/download") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Text("Download Ollama")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.bgApp)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.textPrimary)
                                )
                        }
                        .buttonStyle(.stPlain)

                        Button {
                            Task { await refreshInstalled() }
                        } label: {
                            Text("I installed Ollama — refresh")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                        }
                        .buttonStyle(.stPlain)
                        .disabled(isRefreshing)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.textPrimary.opacity(0.06))
                )
            }

            if let bannerError, ollamaReachable {
                Text(bannerError)
                    .font(Typography.captionSmall)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                if layout == .onboarding {
                    ScrollView {
                        modelList
                            .padding(.trailing, 4)
                    }
                    .frame(maxHeight: 340)
                } else {
                    ScrollView {
                        modelList
                            .padding(.trailing, 4)
                    }
                    .frame(maxHeight: 380)
                }
            }
        }
        .onAppear {
            Task { await refreshInstalled() }
        }
        .onChange(of: ollamaBaseURL) { _, _ in
            Task { await refreshInstalled() }
        }
    }

    private var modelList: some View {
        VStack(spacing: 10) {
            ForEach(OllamaCatalogEntry.orderedForPolish) { entry in
                modelCard(entry)
            }
        }
    }

    private func modelCard(_ entry: OllamaCatalogEntry) -> some View {
        let installed = OllamaPolishClient.isModelInstalled(tag: entry.ollamaTag, installedNames: installedNames)
        let isPulling = pullingTag == entry.ollamaTag
        let isSelected =
            selectedModelTag.trimmingCharacters(in: .whitespacesAndNewlines)
            == entry.ollamaTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let ramTight = deviceRAMGB < entry.suggestedMinRAMGB

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(entry.title)
                            .font(.system(size: layout == .onboarding ? 15 : 14, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                        if let badge = entry.badge {
                            Text(badge.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.textPrimary.opacity(0.08))
                                )
                        }
                    }
                    Text(entry.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.sizeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textMuted)
                    if ramTight {
                        Text("Your Mac has \(deviceRAMGB) GB RAM — this model may run tight; lighter options above are safer.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    if installed {
                        Button {
                            selectedModelTag = entry.ollamaTag
                        } label: {
                            Text(isSelected ? "Selected" : "Use")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.bgApp)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSelected ? Color.accentSuccess.opacity(0.85) : Color.textPrimary)
                                )
                        }
                        .buttonStyle(.stPlain)
                        .disabled(isSelected || isPulling)
                    }
                    Button {
                        Task { await pull(entry) }
                    } label: {
                        Text(isPulling ? "Downloading…" : "Download")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.border.opacity(0.55), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.stPlain)
                    .disabled(isPulling || !ollamaReachable || (pullingTag != nil && pullingTag != entry.ollamaTag))
                }
            }

            if isPulling {
                VStack(alignment: .leading, spacing: 6) {
                    if let pullFraction {
                        ProgressView(value: min(1, max(0, pullFraction)))
                            .controlSize(.small)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(pullStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(3)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.bgCard)
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.textPrimary.opacity(0.22) : Color.textPrimary.opacity(0.08),
                    lineWidth: 1
                )
        )
    }

    private func refreshInstalled() async {
        await MainActor.run {
            isRefreshing = true
            bannerError = nil
        }
        do {
            let names = try await OllamaPolishClient.installedModelNames(baseURLString: ollamaBaseURL)
            await MainActor.run {
                installedNames = names
                ollamaReachable = true
                isRefreshing = false
            }
        } catch {
            await MainActor.run {
                ollamaReachable = false
                installedNames = []
                isRefreshing = false
                bannerError = error.localizedDescription
            }
        }
    }

    private func pull(_ entry: OllamaCatalogEntry) async {
        await MainActor.run {
            pullingTag = entry.ollamaTag
            pullFraction = nil
            pullStatus = "Starting…"
            bannerError = nil
        }
        do {
            try await OllamaPolishClient.pullModel(
                baseURLString: ollamaBaseURL,
                model: entry.ollamaTag
            ) { status, fraction in
                await MainActor.run {
                    pullStatus = status
                    pullFraction = fraction
                }
            }
        } catch {
            await MainActor.run {
                bannerError = error.localizedDescription
                pullingTag = nil
                pullFraction = nil
                pullStatus = ""
            }
            return
        }

        // Pull succeeded — commit selection and dismiss progress even if listing models fails afterward.
        await MainActor.run {
            selectedModelTag = entry.ollamaTag
            pullingTag = nil
            pullFraction = nil
            pullStatus = ""
        }

        do {
            let names = try await OllamaPolishClient.installedModelNames(baseURLString: ollamaBaseURL)
            await MainActor.run {
                installedNames = names
            }
        } catch {
            AppLogger.error(
                "Could not refresh installed Ollama models after a successful pull",
                error: error,
                category: AppLogger.models
            )
            await MainActor.run {
                if !installedNames.contains(entry.ollamaTag) {
                    installedNames.append(entry.ollamaTag)
                }
            }
        }
    }
}
