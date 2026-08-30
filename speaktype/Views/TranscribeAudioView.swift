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
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Text("Transcribe Audio")
                    .font(Typography.displayLarge)
                    .foregroundStyle(Color.textPrimary)
                
                Text("Upload an audio or video file to transcribe")
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.top, 32)
            
            // Main Drop Zone / Action Area
            ZStack {
                RoundedRectangle(cornerRadius: Constants.UI.radiusCard, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [8]))
                    .foregroundStyle(Color.border)
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .contentShape(Rectangle())
                    .clickActionPointerCursor()
                    .onTapGesture {
                        showFileImporter = true
                    }
                    .onDrop(of: [.audio, .movie, .fileURL], isTargeted: nil) { providers in
                        validateAndTranscribe(providers: providers)
                        return true
                    }
                
                VStack(spacing: 20) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.textMuted)
                    
                    Text("Drop audio or video file here")
                        .font(Typography.headlineSmall)
                        .foregroundStyle(Color.textPrimary)
                    
                    Button(action: {
                        showFileImporter = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Upload Audio File")
                        }
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
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 8, height: 8)
                                Text("Stop Recording")
                            }
                            .font(Typography.bodyMedium)
                            .frame(minWidth: 140)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.accentError)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: Constants.UI.radiusControl, style: .continuous))
                        }
                        .buttonStyle(.stPlain)
                        .frame(width: 170, height: 42)
                    } else if isTranscribing {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text(transcribingStatusText)
                                .font(Typography.bodySmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else {
                        Button(action: {
                            Task { _ = await audioRecorder.startRecording() }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "mic.fill")
                                Text("Start Recording")
                            }
                        }
                        .buttonStyle(.stAction)
                        .frame(width: 170, height: 42)
                    }
                }
            }
            .padding(.horizontal, 24)

            Toggle("Polish new transcripts", isOn: $polishNewTranscripts)
                .font(Typography.bodyMedium)
                .toggleStyle(.checkbox)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Transcription Result
            if !historyService.items.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(historyService.items) { item in
                            transcriptCard(item)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }

            if let actionError {
                Text(actionError)
                    .font(Typography.captionSmall)
                    .foregroundStyle(Color.accentError)
            }
            
            Spacer()
        }
        .background(Color.clear)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    .font(Typography.captionSmall)
                    .foregroundStyle(Color.textMuted)
                Spacer()
                if workingItemID == item.id { ProgressView().controlSize(.small) }
            }

            Text(text)
                .font(Typography.bodyMedium)
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                actionButton("Raw", icon: "text.alignleft") { displayedVersion[item.id] = .raw }
                actionButton("Polish", icon: "wand.and.stars") { polish(item) }
                actionButton("Summary", icon: "list.bullet.rectangle") { summarize(item) }
                actionButton("Markdown", icon: "square.and.arrow.down") { exportMarkdown(item) }
                Spacer()
            }
            .disabled(workingItemID != nil)
        }
        .themedCard()
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).frame(minWidth: 92) }
            .buttonStyle(.stSecondary)
            .frame(height: 36)
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
