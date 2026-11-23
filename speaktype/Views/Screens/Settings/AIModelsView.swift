import SwiftUI

/// Screen for managing AI transcription models
struct AIModelsView: View {
    // MARK: - Properties

    @StateObject private var downloadService = ModelDownloadService.shared
    @AppStorage(wrappedValue: SelectedModelPreference.recommendedVariant(), SelectedModelPreference.storageKey) private var selectedModel: String
    @State private var models = AIModel.availableModels

    // MARK: - Computed Properties

    var selectedModelName: String {
        models.first(where: { $0.variant == selectedModel })?.name ?? "No model downloaded yet"
    }

    private var hasAnyModelDownloaded: Bool {
        downloadService.downloadProgress.values.contains { $0 >= 1.0 }
    }

    // MARK: - Body

    private var recommendedName: String {
        AIModel.recommendedModel(forDeviceRAMGB: WhisperService.deviceRAMGB).name
    }

    var body: some View {
        PageScaffold(
            title: "AI Models",
            subtitle: "Recommended for your Mac (\(WhisperService.deviceRAMGB)GB RAM): **\(recommendedName)**",
            subtitleHelp: "First transcription after selecting a model may take 10-30 seconds while the AI loads.",
            spacing: 24
        ) {
            // Before any download, the default-model slot becomes the "get started" hint.
            if hasAnyModelDownloaded {
                currentModelCard
            } else {
                setupBanner
            }
            modelsListSection
        }
        .onAppear {
            Task {
                await downloadService.refreshDownloadedModels()
            }
        }
    }

    // MARK: - Subviews

    private var currentModelCard: some View {
        HStack {
            Text("Default model")
                .font(Typography.bodyMedium)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(selectedModelName)
                .font(Typography.labelLarge)
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .themedCard(padding: 0)
    }

    private var modelsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Available Models")

            VStack(spacing: 0) {
                ForEach(Array($models.enumerated()), id: \.element.id) { index, $model in
                    if index > 0 {
                        RowDivider().padding(.horizontal, 16)
                    }
                    ModelRow(model: $model, selectedModel: $selectedModel)
                }
            }
            .themedCard(padding: 0)
        }
    }

    private var setupBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Download a Model to Get Started")
                .font(Typography.labelLarge)
                .foregroundStyle(Color.textPrimary)

            Text("Choose a model below to enable voice transcription. We recommend **\(recommendedName)** for your Mac.")
                .font(Typography.bodySmall)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(padding: 16)
    }
}

// MARK: - Preview

#Preview {
    AIModelsView()
        .background(Color.black)
}
