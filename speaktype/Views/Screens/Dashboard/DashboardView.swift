import AVKit
import AppKit
import CoreMedia
import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @Binding var selection: SidebarItem?
    @StateObject private var historyService = HistoryService.shared
    // Reuse the shared instance instead of spinning up a second recorder (and a second
    // synchronous device enumeration) on the main thread while the window is appearing —
    // that duplicate init was a source of the spinning-cursor stall on launch.
    private var audioRecorder: AudioRecordingService { .shared }
    private var whisperService: WhisperService { WhisperService.shared }
    @State private var leftColumnHeight: CGFloat = 0

    // Trial & License
    @EnvironmentObject var trialManager: TrialManager
    @EnvironmentObject var licenseManager: LicenseManager

    @AppStorage(wrappedValue: SelectedModelPreference.recommendedVariant(), SelectedModelPreference.storageKey) private var selectedModel: String
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage: String = "auto"
    @AppStorage("selectedHotkey") private var selectedHotkey: HotkeyOption = .fn
    @State private var showFileImporter = false
    @State private var isTranscribing = false
    @State private var transcriptionStatus = ""

    @State private var metrics = DashboardHistoryMetrics(entries: [], now: .now)

    var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Welcome back"
        }
    }

    var body: some View {
        PageScaffold(title: timeBasedGreeting) {
            // Trial Banner - Hidden (logic kept for future use)
            // if !licenseManager.isPro {
            //     TrialBanner(status: trialManager.trialStatus)
            // }

            StatsCard(
                wordCount: metrics.wordCount,
                timeSaved: metrics.wordCount / 40,
                todayCount: metrics.todayCount,
                allTimeCount: metrics.allTimeCount,
                weeklyData: metrics.weeklyData
            )

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Recent transcriptions") {
                    if !historyService.items.isEmpty {
                        Button(action: { selection = .history }) {
                            HStack(spacing: 4) {
                                Text("View all")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .font(Typography.labelMedium)
                            .foregroundStyle(Color.textSecondary)
                        }
                        .buttonStyle(.stPlain)
                    }
                }

                if historyService.items.isEmpty {
                    VStack(spacing: 6) {
                        Text("No transcriptions yet")
                            .font(Typography.bodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        Text("Press \(selectedHotkey.configuredLabel) to start recording")
                            .font(Typography.bodySmall)
                            .foregroundStyle(Color.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .themedCard(padding: 0)
                } else {
                    VStack(spacing: 0) {
                        let recent = Array(historyService.items.prefix(5))
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, item in
                            RecentTranscriptionRow(item: item)
                            if index < recent.count - 1 {
                                RowDivider().padding(.horizontal, 16)
                            }
                        }
                    }
                    .themedCard(padding: 0)
                }
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
        // No model load on appear: opening the window must not pull ~1 GB into memory. The
        // model loads on demand when a transcription actually runs locally.
        .task(id: historyService.statsRevision) {
            let entries = historyService.statsEntries
            let snapshot = await Task.detached(priority: .userInitiated) {
                DashboardHistoryMetrics(entries: entries, now: .now)
            }.value
            guard !Task.isCancelled else { return }
            metrics = snapshot
        }
    }

    // MARK: - Helpers

    private func formatTimeSaved(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = Double(minutes) / 60.0
            return String(format: "%.1fh", hours)
        }
    }

    private func formatDurationHighLevel(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins < 60 {
            return "\(mins)m"
        } else {
            let hours = Double(mins) / 60.0
            return String(format: "%.1fh", hours)
        }
    }

    // MARK: - Actions

    private func toggleRecording() {
        if audioRecorder.isRecording {
            Task {
                if let url = await audioRecorder.stopRecording() {
                    startTranscription(url: url, ownsFile: true)
                }
            }
        } else {
            Task { _ = await audioRecorder.startRecording() }
        }
    }

    private func handleFileSelection(url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                url.lastPathComponent)
            try? FileManager.default.removeItem(at: tempURL)
            try FileManager.default.copyItem(at: url, to: tempURL)
            startTranscription(url: tempURL, ownsFile: true)
        } catch {
            print("Error copying file: \(error)")
            startTranscription(url: url, ownsFile: false)
        }
    }

    private func startTranscription(url: URL, ownsFile: Bool) {
        Task {
            isTranscribing = true
            transcriptionStatus = "Transcribing..."

            do {
                // Coordinator picks on-device vs cloud per the user's mode + machine resources,
                // self-heals a local model load, and falls back automatically.
                let outcome = try await TranscriptionCoordinator.transcribe(audioFile: url, language: transcriptionLanguage)
                if await TranscriptionFinalizer.willPolishNextTranscript() {
                    await MainActor.run { transcriptionStatus = "Polishing..." }
                }
                let finalText = await TranscriptionFinalizer.finalizeTranscript(rawTranscript: outcome.text)
                let duration = try await getAudioDuration(url: url)

                DispatchQueue.main.async {
                    historyService.addItem(
                        transcript: finalText,
                        duration: duration,
                        audioFileURL: url,
                        modelUsed: outcome.modelLabel,
                        transcriptionTime: outcome.transcriptionTime,
                        provider: outcome.provider.rawValue,
                        estimatedCostUSD: outcome.estimatedCostUSD,
                        rawTranscript: outcome.text,
                        polishedTranscript: finalText == outcome.text ? nil : finalText
                    )
                    transcriptionStatus = "Done!"
                    isTranscribing = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        transcriptionStatus = ""
                    }
                }
            } catch {
                // Keep the audio of our own recordings as a failed History item to retry later.
                if ownsFile {
                    let duration = (try? await getAudioDuration(url: url)) ?? 0
                    historyService.addFailedItem(
                        audioFileURL: url, duration: duration,
                        errorMessage: error.localizedDescription)
                }
                DispatchQueue.main.async {
                    transcriptionStatus = "Error"
                    isTranscribing = false
                }
            }
        }
    }

    private func getAudioDuration(url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }
}

// MARK: - Stats Card

/// One quiet strip: four numbers side by side, then this week's activity underneath.
struct StatsCard: View {
    let wordCount: Int
    let timeSaved: Int
    let todayCount: Int
    let allTimeCount: Int
    let weeklyData: [(day: String, count: Int)]

    private var totalThisWeek: Int { weeklyData.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                StatBlock(value: wordCount.formatted(), label: "Words transcribed")
                statDivider
                StatBlock(value: "\(timeSaved)m", label: "Time saved typing")
                statDivider
                StatBlock(value: "\(allTimeCount)", label: "Total transcriptions")
                statDivider
                StatBlock(value: "\(todayCount)", label: "Transcriptions today")
            }
            .padding(.vertical, 18)

            RowDivider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("This week")
                        .font(Typography.labelMedium)
                        .foregroundStyle(Color.textPrimary)
                    Text("\(totalThisWeek) transcriptions")
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(Color.textMuted)
                }
                WeekBars(weeklyData: weeklyData)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(padding: 0)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.border.opacity(0.6))
            .frame(width: 0.5)
            .padding(.vertical, 2)
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = Double(minutes) / 60.0
        return String(format: "%.1fh", hours)
    }
}

/// Seven slim bars, one per day. Empty days stay as a faint baseline.
private struct WeekBars: View {
    let weeklyData: [(day: String, count: Int)]

    var body: some View {
        let maxCount = max(weeklyData.map { $0.count }.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(weeklyData.enumerated()), id: \.offset) { _, data in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(data.count > 0 ? Color.textPrimary.opacity(0.85) : Color.border.opacity(0.5))
                        .frame(height: max(CGFloat(data.count) / CGFloat(maxCount) * 44, 3))
                        .help(data.count > 0 ? "\(data.count) transcriptions" : "")
                    Text(data.day)
                        .font(Typography.captionSmall)
                        .foregroundStyle(data.count > 0 ? Color.textSecondary : Color.textMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 64, alignment: .bottom)
    }
}

// MARK: - Stat Block

struct StatBlock: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Typography.statValueM)
                .tracking(-0.3)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Color.textMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

// MARK: - Recent Transcription Row

struct RecentTranscriptionRow: View {
    let item: HistoryItem
    private var audioPlayer: AudioPlayerService { .shared }
    @State private var isHovered = false
    @State private var showCopySuccess = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.isFailed ? "Transcription failed" : (item.transcript.isEmpty ? "Empty transcription" : item.transcript))
                    .font(Typography.bodyMedium)
                    .foregroundStyle(item.isFailed ? Color.textSecondary : Color.textPrimary)
                    .lineLimit(2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text([timeAgo(item.date), (item.wordCount == 1 ? "1 word" : "\(item.wordCount) words"), formatDuration(item.duration)]
                    .joined(separator: "  ·  "))
                    .font(Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Quick actions: present but quiet until the row is hovered.
            HStack(spacing: 2) {
                if !item.isFailed {
                    rowAction(
                        icon: showCopySuccess ? "checkmark" : "doc.on.doc",
                        help: showCopySuccess ? "Copied" : "Copy",
                        tint: showCopySuccess ? Color.accentSuccess : Color.textSecondary,
                        action: copyToClipboard
                    )
                }
                if item.hasAudio, let audioURL = item.audioFileURL {
                    rowAction(
                        icon: isPlayingThisItem ? "pause.fill" : "play.fill",
                        help: isPlayingThisItem ? "Pause" : "Play",
                        tint: Color.textSecondary,
                        action: { togglePlayback(audioURL) }
                    )
                }
            }
            .opacity(isHovered || showCopySuccess || isPlayingThisItem ? 1 : 0.35)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isHovered ? Color.bgHover.opacity(0.45) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private func rowAction(icon: String, help: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.stPlain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var isPlayingThisItem: Bool {
        audioPlayer.isPlaying && audioPlayer.currentAudioURL == item.audioFileURL
    }

    /// Same shared player the History screen uses: load this row's audio, then play/pause.
    private func togglePlayback(_ url: URL) {
        if isPlayingThisItem {
            audioPlayer.pause()
        } else {
            Task {
                if audioPlayer.currentAudioURL != url {
                    guard await audioPlayer.loadAudio(from: url) else { return }
                }
                audioPlayer.play()
            }
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.transcript, forType: .string)

        withAnimation {
            showCopySuccess = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopySuccess = false
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let mins = seconds / 60
            let secs = seconds % 60
            return "\(mins)m \(secs)s"
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

// MARK: - Preference Key
struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
