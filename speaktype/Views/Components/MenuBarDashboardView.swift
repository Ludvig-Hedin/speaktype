import AppKit
import SwiftUI

struct MenuBarDashboardView: View {
    @StateObject private var historyService = HistoryService.shared

    let openDashboard: () -> Void
    let startRecording: () -> Void
    let quit: () -> Void

    @AppStorage("hotkeyEnabled") private var hotkeyEnabled: Bool = true
    @AppStorage("selectedHotkey") private var selectedHotkey: HotkeyOption = .fn
    @AppStorage("recordingMode") private var recordingMode: Int = 0

    @Environment(\.dismiss) private var dismiss

    private let statsColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var todayCount: Int {
        historyService.transcriptionCount(since: Calendar.current.startOfDay(for: Date()))
    }

    private var totalCount: Int {
        historyService.transcriptionCount()
    }

    private var totalWords: Int {
        historyService.totalWordCount()
    }

    private var timeSavedMinutes: Int {
        totalWords / 40
    }

    private var recentItems: [HistoryItem] {
        Array(historyService.items.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            shortcutControlsSection
            statsGrid
            recentTranscriptsSection
            actionRow
        }
        .padding(16)
        .frame(width: 388)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bgHover)
                .frame(width: 40, height: 40)
                .overlay {
                    Image("MenuBarWave")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(Color.textPrimary)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("SpeakType")
                    .font(Typography.headlineLarge)
                    .foregroundStyle(Color.textPrimary)

                Text(summaryLine)
                    .font(Typography.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 12)

            Button(action: openDashboard) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Open")
                        .font(Typography.labelSmall)
                }
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.bgHover)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.stPlain)
        }
    }

    // MARK: - Shortcut Controls

    private var shortcutControlsSection: some View {
        VStack(spacing: 10) {
            // Row 1: Hotkey enable toggle + shortcut picker
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 16)

                Text("Hotkey")
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                // Shortcut picker
                Menu {
                    ForEach(HotkeyOption.allCases) { option in
                        if option == .custom {
                            Divider()
                        }
                        Button(action: { selectedHotkey = option }) {
                            HStack {
                                Text(option.displayName)
                                if selectedHotkey == option {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(shortcutLabel)
                            .font(Typography.labelSmall)
                            .foregroundStyle(Color.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.bgHover)
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .opacity(hotkeyEnabled ? 1 : 0.5)
                .disabled(!hotkeyEnabled)

                // Enable/disable toggle
                Toggle("", isOn: $hotkeyEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.85)
            }

            // Divider
            Divider()
                .opacity(0.5)

            // Row 2: Recording mode picker
            HStack(spacing: 8) {
                Image(systemName: recordingMode == 0 ? "mic.fill" : "mic.badge.plus")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textMuted)
                    .frame(width: 16)

                Text("Mode")
                    .font(Typography.bodyMedium)
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                MenuBarModePicker(recordingMode: $recordingMode)
            }
            .opacity(hotkeyEnabled ? 1 : 0.5)
        }
        .padding(12)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.border, lineWidth: 1)
        }
    }

    private var shortcutLabel: String {
        if selectedHotkey == .custom {
            return CustomShortcutStorage.isSet
                ? CustomShortcutStorage.displayString
                : "Custom…"
        }
        return selectedHotkey.displayName
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(columns: statsColumns, spacing: 10) {
            MenuBarStatCard(
                title: "Today",
                value: "\(todayCount)",
                icon: "calendar",
                tint: Color.accentBlue
            )
            MenuBarStatCard(
                title: "Total",
                value: "\(totalCount)",
                icon: "waveform",
                tint: Color.accentPrimary
            )
            MenuBarStatCard(
                title: "Words",
                value: abbreviatedCount(totalWords),
                icon: "text.word.spacing",
                tint: Color.accentSuccess
            )
            MenuBarStatCard(
                title: "Saved",
                value: formatTimeSaved(timeSavedMinutes),
                icon: "timer",
                tint: Color.accentWarning
            )
        }
    }

    // MARK: - Recent Transcripts

    private var recentTranscriptsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Last 5 transcripts")
                    .font(Typography.headlineMedium)
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                Text("Click to copy")
                    .font(Typography.captionSmall)
                    .foregroundStyle(Color.textMuted)
            }

            if recentItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No transcripts yet")
                        .font(Typography.bodyMedium)
                        .foregroundStyle(Color.textPrimary)

                    Text("Your latest recordings will appear here after transcription.")
                        .font(Typography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.border, lineWidth: 1)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(recentItems) { item in
                        MenuBarTranscriptRow(item: item)
                    }
                }
            }
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        VStack(spacing: 8) {
            // Start Recording — primary CTA
            Button(action: handleStartRecording) {
                HStack(spacing: 7) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Start Recording")
                        .font(Typography.labelMedium)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.stPlain)

            HStack(spacing: 10) {
                Button(action: openDashboard) {
                    Label("Open Dashboard", systemImage: "rectangle.grid.2x2")
                        .font(Typography.labelMedium)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.bgHover)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.stPlain)

                Button(action: quit) {
                    Label("Quit", systemImage: "xmark.circle")
                        .font(Typography.labelMedium)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.bgHover)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.stPlain)
            }
        }
    }

    private func handleStartRecording() {
        // Dismiss the popup first, then start recording after it has closed
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            startRecording()
        }
    }

    // MARK: - Helpers

    private var summaryLine: String {
        if totalCount == 0 {
            return "Ready when you are"
        }
        let transcriptWord = todayCount == 1 ? "transcript" : "transcripts"
        return "\(todayCount) \(transcriptWord) today • \(abbreviatedCount(totalWords)) words total"
    }

    private func abbreviatedCount(_ count: Int) -> String {
        switch count {
        case 1_000_000...:
            return String(format: "%.1fM", Double(count) / 1_000_000)
                .replacingOccurrences(of: ".0", with: "")
        case 1_000...:
            return String(format: "%.1fK", Double(count) / 1_000)
                .replacingOccurrences(of: ".0", with: "")
        default:
            return "\(count)"
        }
    }

    private func formatTimeSaved(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = Double(minutes) / 60
        return String(format: "%.1fh", hours).replacingOccurrences(of: ".0", with: "")
    }
}

// MARK: - Compact mode picker (menu bar)

private struct MenuBarModePicker: View {
    @Binding var recordingMode: Int

    var body: some View {
        HStack(spacing: 3) {
            modeSegment(tag: 0, label: "Hold")
            modeSegment(tag: 1, label: "Toggle")
        }
        .padding(3)
        .background(
            Capsule(style: .continuous).fill(Color.bgHover.opacity(0.6))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.border.opacity(0.35), lineWidth: 0.5)
        )
    }

    private func modeSegment(tag: Int, label: String) -> some View {
        let selected = recordingMode == tag
        return Button { recordingMode = tag } label: {
            Text(label)
                .font(Typography.captionSmall)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? Color.textPrimary : Color.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if selected {
                        Capsule(style: .continuous).fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.textPrimary.opacity(selected ? 0.12 : 0), lineWidth: 1)
                )
        }
        .buttonStyle(.stPlain)
    }
}

// MARK: - Stat card

private struct MenuBarStatCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)

                Text(title)
                    .font(Typography.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.border, lineWidth: 1)
        }
    }
}

// MARK: - Transcript row

private struct MenuBarTranscriptRow: View {
    let item: HistoryItem

    private var wordCount: Int {
        item.transcript.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    var body: some View {
        Button(action: copyTranscript) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentBlue)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.transcript.isEmpty ? "Empty transcription" : item.transcript)
                        .font(Typography.bodySmall)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        Label(relativeDateText(item.date), systemImage: "clock")
                            .labelStyle(.titleAndIcon)

                        Text("\(wordCount) words")

                        Spacer(minLength: 0)

                        Image(systemName: "doc.on.doc")
                    }
                    .font(Typography.captionSmall)
                    .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.border, lineWidth: 1)
            }
        }
        .buttonStyle(.stPlain)
    }

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.transcript, forType: .string)
    }

    private func relativeDateText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
