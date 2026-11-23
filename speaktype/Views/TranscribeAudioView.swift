import SwiftUI
import AppKit
import AVFoundation
import CoreMedia
import UniformTypeIdentifiers

struct TranscribeAudioView: View {
    @StateObject private var audioRecorder = AudioRecordingService.shared
    @StateObject private var historyService = HistoryService.shared
    private var whisperService: WhisperService { WhisperService.shared }
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage: String = "auto"
    @State private var transcribedText: String = ""
    @State private var isTranscribing = false
    @State private var transcribingStatusText = "Transcribing..."
    @State private var showFileImporter = false
    @State private var polishNewTranscripts = false
    @State private var workingItemID: UUID?
    @State private var displayedVersion: [UUID: TranscriptVersion] = [:]
    @State private var actionError: String?
    
    var body: some View {
        PageScaffold(
            title: "Transcribe Audio",
            subtitle: "Upload an audio or video file to transcribe",
            spacing: 24
        ) {
            VStack(alignment: .leading, spacing: 12) {
                dropZone

                Toggle("Polish new transcripts", isOn: $polishNewTranscripts)
                    .font(Typography.bodySmall)
                    .foregroundStyle(Color.textSecondary)
                    .toggleStyle(.checkbox)

                if let actionError {
                    Text(actionError)
                        .font(Typography.caption)
                        .foregroundStyle(Color.accentError)
                }
            }

            let transcripts = historyService.items.filter { !$0.isFailed }
            if !transcripts.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(Array(transcripts.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            RowDivider().padding(.horizontal, 16)
                        }
                        transcriptCard(item)
                    }
                }
                .themedCard(padding: 0)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    handleFileSelection(url: url)
                }
            case .failure(let error):
                print("File selection error: \(error.localizedDescription)")
            }
        }
        .onAppear {
            if TranscriptionModeUserDefaults.mode != .remoteOnly {
                Task {
                if !whisperService.isInitialized {
                    try? await whisperService.initialize()
                }
                }
            }
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 16) {
            Text("Drop audio or video file here")
                .font(Typography.bodyMedium)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 10) {
                Button(action: { showFileImporter = true }) {
                    Text("Upload Audio File")
                }
                .buttonStyle(.stSecondary)

                Text("or")
                    .font(Typography.bodySmall)
                    .foregroundStyle(Color.textMuted)

                if audioRecorder.isRecording {
                    Button(action: {
                        Task {
                            if let url = await audioRecorder.stopRecording() {
                                startTranscription(url: url, ownsFile: true)
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Circle().fill(Color.white).frame(width: 7, height: 7)
                            Text("Stop Recording")
                        }
                        .font(Typography.labelMedium.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Color.accentError,
                            in: RoundedRectangle(cornerRadius: Constants.UI.radiusSmall, style: .continuous)
                        )
                    }
                    .buttonStyle(.stPlain)
                } else if isTranscribing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(transcribingStatusText)
                            .font(Typography.bodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                } else {
                    Button(action: {
                        Task { _ = await audioRecorder.startRecording() }
                    }) {
                        Text("Start Recording")
                    }
                    .buttonStyle(.stAction)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(
            RoundedRectangle(cornerRadius: Constants.UI.radiusCard, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                .foregroundStyle(Color.border)
        )
        .contentShape(Rectangle())
        .onTapGesture { showFileImporter = true }
        .onDrop(of: [.audio, .movie, .fileURL], isTargeted: nil) { providers in
            validateAndTranscribe(providers: providers)
            return true
        }
    }
    
    private func handleFileSelection(url: URL) {
        // Access security scoped resource if needed (for file picker)
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        
        // Create a copy or use the URL directly.
        // For simplicity in this context, we'll try to use it directly but ensure we stop accessing later if needed.
        // However, since startTranscription is async, we might lose access.
        // Better pattern: Copy to temp directory if possible, or keep access open during transcription.
        // Given WhisperKit might need file access, let's copy to a temp location to be safe and avoid scope issues.
        
        do {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: tempURL) // Clean up if exists
            try FileManager.default.copyItem(at: url, to: tempURL)
            
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            
            startTranscription(url: tempURL, ownsFile: true)
        } catch {
            print("Error copying file: \(error)")
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
            // Fallback: try original URL if copy fails
            startTranscription(url: url, ownsFile: false)
        }
    }
    
    private func validateAndTranscribe(providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) || 
               provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                
                provider.loadFileRepresentation(forTypeIdentifier: UTType.content.identifier) { url, error in
                    if let url = url {
                        // LoadFileRepresentation gives us a temporary URL that might not persist.
                        // We should copy it immediately.
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                        do {
                            try? FileManager.default.removeItem(at: tempURL)
                            try FileManager.default.copyItem(at: url, to: tempURL)
                            
                            DispatchQueue.main.async {
                                startTranscription(url: tempURL, ownsFile: true)
                            }
                        } catch {
                            print("Error copying dropped file: \(error)")
                        }
                    }
                }
                return // Only handle the first valid file
            }
        }
    }
    
    private func startTranscription(url: URL, ownsFile: Bool) {
        Task {
            isTranscribing = true
            transcribingStatusText = "Transcribing..."
            do {
                let outcome = try await TranscriptionCoordinator.transcribe(audioFile: url, language: transcriptionLanguage)
                if polishNewTranscripts {
                    await MainActor.run { transcribingStatusText = "Polishing..." }
                }
                let rawTranscript = outcome.text
                guard !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw RemoteTranscriptionClient.ClientError.emptyResponse
                }
                transcribedText = polishNewTranscripts
                    ? await TranscriptionFinalizer.polishTranscriptOnDemand(rawTranscript)
                    : rawTranscript
                // Save to History
                let duration = try await getAudioDuration(url: url)
                HistoryService.shared.addItem(
                    transcript: transcribedText, duration: duration, audioFileURL: url,
                    modelUsed: outcome.modelLabel, transcriptionTime: outcome.transcriptionTime,
                    provider: outcome.provider.rawValue,
                    estimatedCostUSD: outcome.estimatedCostUSD,
                    rawTranscript: rawTranscript,
                    polishedTranscript: polishNewTranscripts ? transcribedText : nil)
            } catch {
                if ownsFile { try? FileManager.default.removeItem(at: url) }
                transcribedText = "Error: \(error.localizedDescription)"
            }
            isTranscribing = false
        }
    }
    
    private func getAudioDuration(url: URL) async throws -> TimeInterval {
        // Async duration check using AVURLAsset
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    @ViewBuilder
    private func transcriptCard(_ item: HistoryItem) -> some View {
        let version = displayedVersion[item.id] ?? (item.polishedTranscript == nil ? .raw : .polished)
        let text = text(for: item, version: version)
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(Typography.bodyMedium)
                .foregroundStyle(Color.textPrimary)
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    .font(Typography.caption)
                    .foregroundStyle(Color.textMuted)
                if workingItemID == item.id { ProgressView().controlSize(.mini) }
                Spacer()
                actionButton("Raw", icon: "text.alignleft", help: "Show the raw transcript", isActive: version == .raw) {
                    displayedVersion[item.id] = .raw
                }
                actionButton("Polish", icon: "wand.and.stars", help: "Polish this transcript", isActive: version == .polished) {
                    polish(item)
                }
                actionButton("Summary", icon: "list.bullet.rectangle", help: "Summarize this transcript", isActive: version == .summary) {
                    summarize(item)
                }
                actionButton("Markdown", icon: "square.and.arrow.down", help: "Export as a Markdown file", isActive: false) {
                    exportMarkdown(item)
                }
            }
            .disabled(workingItemID != nil)
        }
        .padding(16)
    }

    /// Compact row action. The version currently on screen (Raw / Polish / Summary) reads as selected.
    private func actionButton(
        _ title: String, icon: String, help: String, isActive: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
            }
            .font(Typography.labelSmall)
            .foregroundStyle(isActive ? Color.textPrimary : Color.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.bgHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.stPlain)
        .help(help)
    }

    private func text(for item: HistoryItem, version: TranscriptVersion) -> String {
        switch version {
        case .raw: return item.rawTranscript ?? item.transcript
        case .polished: return item.polishedTranscript ?? item.transcript
        case .summary: return item.summary ?? item.transcript
        }
    }

    private func polish(_ item: HistoryItem) {
        workingItemID = item.id
        actionError = nil
        Task {
            let source = item.rawTranscript ?? item.transcript
            let result = await TranscriptionFinalizer.polishTranscriptOnDemand(source)
            await MainActor.run {
                historyService.setPolishedTranscript(result, for: item.id)
                displayedVersion[item.id] = .polished
                workingItemID = nil
            }
        }
    }

    private func summarize(_ item: HistoryItem) {
        workingItemID = item.id
        actionError = nil
        Task {
            do {
                let result = try await TranscriptionFinalizer.summarizeTranscript(item.rawTranscript ?? item.transcript)
                await MainActor.run {
                    historyService.setSummary(result, for: item.id)
                    displayedVersion[item.id] = .summary
                    workingItemID = nil
                }
            } catch {
                await MainActor.run {
                    actionError = error.localizedDescription
                    workingItemID = nil
                }
            }
        }
    }

    private func exportMarkdown(_ item: HistoryItem) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "SpeakType-Transcript.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let raw = item.rawTranscript ?? item.transcript
        var markdown = "# Transcript\n\nRecorded: \(item.date.formatted(date: .long, time: .shortened))\n\n## Raw\n\n\(raw)\n"
        if let polished = item.polishedTranscript { markdown += "\n## Polished\n\n\(polished)\n" }
        if let summary = item.summary { markdown += "\n## Summary\n\n\(summary)\n" }
        do { try markdown.write(to: url, atomically: true, encoding: .utf8) }
        catch { actionError = error.localizedDescription }
    }
}

private enum TranscriptVersion { case raw, polished, summary }
