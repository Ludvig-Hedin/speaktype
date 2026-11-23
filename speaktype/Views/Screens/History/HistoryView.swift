import SwiftUI

struct HistoryView: View {
    @StateObject private var historyService = HistoryService.shared
    @StateObject private var audioPlayer = AudioPlayerService.shared
    @State private var showDeleteAlert = false
    @State private var itemPendingDeletion: HistoryItem? = nil
    @State private var expandedItemId: UUID? = nil
    @State private var showCopyToast = false
    @AppStorage("selectedHotkey") private var selectedHotkey: HotkeyOption = .fn
    
    var body: some View {
        PageScaffold(
            title: "History",
            subtitle: historyService.items.isEmpty ? nil : "\(historyService.items.count) transcriptions",
            spacing: 24
        ) {
            if !historyService.items.isEmpty {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Clear All")
                    }
                    .font(Typography.labelMedium)
                    .foregroundStyle(Color.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.stPlain)
            }
        } content: {
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
                .padding(.vertical, 48)
                .themedCard(padding: 0)
            } else {
                // One list, hairline rows — not a stack of separate cards.
                LazyVStack(spacing: 0) {
                    ForEach(Array(historyService.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            RowDivider().padding(.horizontal, 16)
                        }
                        HistoryCard(
                            item: item,
                            isExpanded: expandedItemId == item.id,
                            onToggle: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    if expandedItemId == item.id {
                                        expandedItemId = nil
                                        audioPlayer.stop()
                                    } else {
                                        expandedItemId = item.id
                                        if let audioURL = item.audioFileURL,
                                           FileManager.default.fileExists(atPath: audioURL.path) {
                                            audioPlayer.loadAudio(from: audioURL)
                                        } else {
                                            audioPlayer.reset()
                                        }
                                    }
                                }
                            },
                            onCopy: { copyToClipboard(text: item.transcript) },
                            onDelete: { itemPendingDeletion = item },
                            onRetry: {
                                Task { await historyService.retryTranscription(id: item.id) }
                            },
                            isRetrying: historyService.retryingItemIDs.contains(item.id),
                            audioPlayer: audioPlayer
                        )
                    }
                }
                .themedCard(padding: 0)
            }
        }
        .overlay(alignment: .bottom) {
            if showCopyToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentBlue)
                    Text("Text Copied")
                        .font(Typography.labelMedium)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Material.ultraThinMaterial)
                .background(Color.black.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: Constants.UI.radiusCard, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .padding(.bottom, 30)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Clear All History?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                historyService.clearAll()
            }
        } message: {
            Text("This removes your saved transcripts, but keeps your statistics history.")
        }
        .alert(
            "Delete Transcript?",
            isPresented: Binding(
                get: { itemPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        itemPendingDeletion = nil
                    }
                }
            ),
            presenting: itemPendingDeletion
        ) { item in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if expandedItemId == item.id {
                    expandedItemId = nil
                    audioPlayer.reset()
                }
                historyService.deleteItem(id: item.id)
                itemPendingDeletion = nil
            }
        } message: { item in
            if let audioURL = item.audioFileURL,
               FileManager.default.fileExists(atPath: audioURL.path) {
                Text("This will remove the transcript and its saved audio file.")
            } else {
                Text("This will remove the transcript entry from your history.")
            }
        }
    }
    
    private func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        withAnimation {
            showCopyToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopyToast = false
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%dm %ds", minutes, seconds)
    }
    
    private func formatDurationShort(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        return "\(seconds) s"
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - History Row Component

struct HistoryCard: View {
    let item: HistoryItem
    let isExpanded: Bool
    let onToggle: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void
    let isRetrying: Bool
    @ObservedObject var audioPlayer: AudioPlayerService
    @State private var isHovered = false

    private let dateColumnWidth: CGFloat = 40

    private var audioFileExists: Bool {
        guard let audioURL = item.audioFileURL else { return false }
        return FileManager.default.fileExists(atPath: audioURL.path)
    }

    var wordCount: Int {
        item.transcript.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                    // Date
                    VStack(alignment: .center, spacing: 1) {
                        Text(item.date.formatted(.dateTime.day()))
                            .font(Typography.headlineMedium)
                            .monospacedDigit()
                            .foregroundStyle(Color.textPrimary)
                        Text(item.date.formatted(.dateTime.month(.abbreviated)))
                            .font(Typography.captionSmall)
                            .foregroundStyle(Color.textMuted)
                    }
                    .frame(width: dateColumnWidth)

                    VStack(alignment: .leading, spacing: 6) {
                        if item.isFailed {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.accentWarning)
                                Text("Transcription failed")
                                    .font(Typography.bodyMedium)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        } else if isExpanded {
                            // Same spot as the preview, so expanding only grows the text.
                            Text(item.transcript)
                                .font(Typography.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(item.transcript)
                                .font(Typography.bodyMedium)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(2)
                                .lineSpacing(2)
                                .multilineTextAlignment(.leading)
                        }

                        Text([
                            item.date.formatted(date: .omitted, time: .shortened),
                            (wordCount == 1 ? "1 word" : "\(wordCount) words"),
                            formatDurationShort(item.duration),
                        ].joined(separator: "  ·  "))
                            .font(Typography.caption)
                            .monospacedDigit()
                            .foregroundStyle(Color.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onToggle) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textMuted)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .opacity(isHovered || isExpanded ? 1 : 0.4)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.stPlain)
                    .padding(.top, -3)
                    .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            // Whole row opens it; once open, clicks are free for selecting text (chevron closes).
            .onTapGesture { if !isExpanded { onToggle() } }
            .accessibilityAddTraits(isExpanded ? [] : .isButton)
            .onHover { isHovered = $0 }

            if isExpanded {
                expandedContent
                    .padding(.leading, 16 + dateColumnWidth + 16)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(isHovered && !isExpanded ? Color.bgHover.opacity(0.4) : Color.clear)
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let failureReason = item.failureReason {
                Text(failureReason)
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .textSelection(.enabled)
            }

            if let audioURL = item.audioFileURL, audioFileExists {
                WaveformView(
                    audioURL: audioURL,
                    currentTime: $audioPlayer.currentTime,
                    duration: $audioPlayer.duration
                )
                .frame(height: 44)
            }

            HStack(spacing: 8) {
                if item.isFailed {
                    Button(action: onRetry) {
                        HStack(spacing: 6) {
                            if isRetrying {
                                ProgressView().controlSize(.mini)
                            }
                            Text(isRetrying ? "Retrying…" : "Retry")
                        }
                    }
                    .buttonStyle(.stSecondary)
                    .disabled(isRetrying || !audioFileExists)
                } else {
                    Button("Copy", action: onCopy)
                        .buttonStyle(.stSecondary)
                }

                if let audioURL = item.audioFileURL, audioFileExists {
                    Button(audioPlayer.isPlaying ? "Pause" : "Play Audio") {
                        if audioPlayer.isPlaying {
                            audioPlayer.pause()
                        } else {
                            audioPlayer.play()
                        }
                    }
                    .buttonStyle(.stSecondary)

                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([audioURL])
                    }
                    .buttonStyle(.stSecondary)
                } else if item.audioFileURL != nil {
                    Text("Audio file missing")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textMuted)
                }

                Spacer(minLength: 8)

                if let model = item.modelUsed {
                    Text(model)
                        .font(Typography.caption)
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textMuted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.stPlain)
                .help("Delete")
                .accessibilityLabel("Delete")
            }
        }
    }

    private func formatDurationShort(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let mins = seconds / 60
            return "\(mins)m"
        }
    }
}
