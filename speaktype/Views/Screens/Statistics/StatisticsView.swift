//
//  StatisticsView.swift
//  speaktype
//
//  Created on 2026-01-19.
//  Statistics view showing daily word transcription trends
//

import Charts
import Combine
import SwiftUI

struct StatisticsView: View {
    @StateObject private var historyService = HistoryService.shared
    private var audioRecorder: AudioRecordingService { .shared }
    @State private var recordingStart: Date?
    @State private var metrics = HistoryPeriodMetrics.empty
    @State private var selectedPeriod: StatisticsPeriod = .week
    @State private var timer: Timer? = nil
    @State private var timeTrigger = Date()

    var body: some View {
        PageScaffold(
            title: "Statistics",
            subtitle: "\(metrics.totalWords) words this \(selectedPeriod.rawValue.lowercased())",
            spacing: 24
        ) {
            periodPicker
        } content: {
            summaryCards
            barChartSection
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onReceive(audioRecorder.$isRecording.removeDuplicates()) { isRecording in
            recordingStart = isRecording ? audioRecorder.recordingStartTime : nil
            if isRecording {
                startTimer()
            } else {
                stopTimer()
                // Force one last update
                timeTrigger = Date()
            }
        }
        .task(id: MetricsRequest(revision: historyService.statsRevision, period: selectedPeriod)) {
            let entries = historyService.statsEntries
            let period = selectedPeriod
            let snapshot = await Task.detached(priority: .userInitiated) {
                HistoryPeriodMetrics(entries: entries, period: period, now: .now)
            }.value
            guard !Task.isCancelled else { return }
            metrics = snapshot
        }
    }

    // MARK: - View Components

    private var periodPicker: some View {
        HStack(spacing: 2) {
            ForEach(StatisticsPeriod.allCases) { period in
                PeriodButton(
                    period: period,
                    isSelected: selectedPeriod == period,
                    action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedPeriod = period
                        }
                    }
                )
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Constants.UI.radiusSmall, style: .continuous)
                .fill(Color.bgHover)
        )
    }

    private var summaryCards: some View {
        HStack(alignment: .top, spacing: 0) {
            StatBlock(value: "\(metrics.totalWords)", label: "Total words")
            summaryDivider
            StatBlock(value: "\(metrics.dailyAverage)", label: "Daily average")
            summaryDivider
            StatBlock(value: "\(metrics.bestDay)", label: "Best day")
            summaryDivider
            StatBlock(value: "\(metrics.transcriptionCount)", label: "Transcriptions")

            // Only surfaces once cloud transcription has actually incurred a cost.
            if metrics.totalCost > 0 {
                summaryDivider
                StatBlock(value: formattedCost, label: "Est. cloud cost")
            }
        }
        .padding(.vertical, 18)
        .themedCard(padding: 0)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color.border.opacity(0.6))
            .frame(width: 0.5)
            .padding(.vertical, 2)
    }

    private struct MetricsRequest: Equatable {
        let revision: Int
        let period: StatisticsPeriod
    }

    private var formattedCost: String {
        let cost = metrics.totalCost
        if cost > 0 && cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", cost)
    }

    private var barChartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Activity")
                    .font(Typography.headlineSmall)
                    .foregroundStyle(Color.textPrimary)

                if metrics.buckets.allSatisfy({ $0.wordCount == 0 }) {
                    emptyChartView
                } else {
                    chartView
                }
            }
            .padding(20)

            RowDivider()

            detailsSection
                .padding(.vertical, 16)
        }
        .themedCard(padding: 0)
    }

    private var emptyChartView: some View {
        VStack(spacing: 6) {
            Text("No activity yet")
                .font(Typography.bodyMedium)
                .foregroundStyle(Color.textPrimary)

            Text("Your transcription statistics will appear here")
                .font(Typography.bodySmall)
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
    }

    private var chartView: some View {
        Chart {
            ForEach(metrics.buckets) { data in
                BarMark(
                    x: .value("Date", data.dateString),
                    y: .value("Words", data.wordCount)
                )
                .foregroundStyle(Color.textPrimary.opacity(0.8))
                .cornerRadius(3)
            }
        }
        .chartXAxis {
            if selectedPeriod == .month {
                // For month view, label every 7 days
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel()
                        .font(Typography.captionSmall)
                        .foregroundStyle(Color.textMuted)
                }
            } else {
                // Week shows each day; year shows months
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(Typography.captionSmall)
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.border.opacity(0.8))
                AxisValueLabel()
                    .font(Typography.captionSmall)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .chartPlotStyle { plotArea in
            plotArea.background(Color.clear)
        }
        .frame(height: 220)
    }

    private var detailsSection: some View {
        HStack(alignment: .top, spacing: 0) {
            DetailCard(
                icon: "number",
                label: "Avg. words per note",
                value: "\(metrics.averageWordsPerTranscription)"
            )
            DetailCard(
                icon: "star.fill",
                label: "Most active day",
                value: mostActiveDay
            )
            DetailCard(
                icon: "clock",
                label: "Total duration",
                value: formattedDuration
            )
        }
    }

    // MARK: - Data Calculations

    private var formattedDuration: String {
        var totalSeconds = metrics.totalDuration
        if let recordingStart {
            totalSeconds += max(0, timeTrigger.timeIntervalSince(recordingStart))
        }

        // Formatting Logic
        if totalSeconds < 60 {
            return "\(Int(totalSeconds))s"
        }

        let minutes = Int(totalSeconds) / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else {
            return "\(remainingMinutes)m"
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            timeTrigger = Date()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private var mostActiveDay: String {
        guard let bucket = metrics.buckets.max(by: { $0.wordCount < $1.wordCount }),
              bucket.wordCount > 0 else { return "N/A" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: bucket.date)
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        StatBlock(value: value, label: label)
            .padding(.vertical, 18)
            .themedCard(padding: 0)
    }
}

/// Secondary figure in the Activity footer: label over value, no icon, no card.
struct DetailCard: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Color.textMuted)
            Text(value)
                .font(Typography.labelLarge)
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

struct PeriodButton: View {
    let period: StatisticsPeriod
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(period.rawValue)
                .font(Typography.labelMedium)
                .foregroundStyle(isSelected ? Color.textPrimary : Color.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Constants.UI.radiusSmall - 2, style: .continuous)
                            .fill(Color.segmentSelected)
                            .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.stPlain)
    }
}

#Preview {
    StatisticsView()
}
