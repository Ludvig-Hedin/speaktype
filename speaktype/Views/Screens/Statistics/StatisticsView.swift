//
//  StatisticsView.swift
//  speaktype
//
//  Created on 2026-01-19.
//  Statistics view showing daily word transcription trends
//

import Charts
import SwiftUI

struct StatisticsView: View {
    @StateObject private var historyService = HistoryService.shared
    @ObservedObject private var audioRecorder = AudioRecordingService.shared
    @State private var selectedPeriod: StatisticsPeriod = .week
    @State private var timer: Timer? = nil
    @State private var timeTrigger = Date()

    var body: some View {
        PageScaffold(
            title: "Statistics",
            subtitle: "\(totalWords(for: selectedPeriod)) words this \(selectedPeriod.rawValue.lowercased())",
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
        .onChange(of: audioRecorder.isRecording) {
            if audioRecorder.isRecording {
                startTimer()
            } else {
                stopTimer()
                // Force one last update
                timeTrigger = Date()
            }
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
            StatBlock(value: "\(totalWords(for: selectedPeriod))", label: "Total words")
            summaryDivider
            StatBlock(value: "\(dailyAverage(for: selectedPeriod))", label: "Daily average")
            summaryDivider
            StatBlock(value: "\(bestDay(for: selectedPeriod))", label: "Best day")
            summaryDivider
            StatBlock(value: "\(transcriptionCount(for: selectedPeriod))", label: "Transcriptions")

            // Only surfaces once cloud transcription has actually incurred a cost.
            if totalCost(for: selectedPeriod) > 0 {
                summaryDivider
                StatBlock(value: formattedCost(for: selectedPeriod), label: "Est. cloud cost")
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

    private func startDate(for period: StatisticsPeriod) -> Date {
        let calendar = Calendar.current
        let now = Date()
        switch period {
        case .week: return calendar.date(byAdding: .day, value: -6, to: now)!
        case .month: return calendar.date(byAdding: .day, value: -29, to: now)!
        case .year: return calendar.date(byAdding: .day, value: -364, to: now)!
        }
    }

    private func totalCost(for period: StatisticsPeriod) -> Double {
        historyService.totalEstimatedCostUSD(since: startDate(for: period))
    }

    private func formattedCost(for period: StatisticsPeriod) -> String {
        let cost = totalCost(for: period)
        if cost > 0 && cost < 0.01 { return "<$0.01" }
        return String(format: "$%.2f", cost)
    }

    private var barChartSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Activity")
                    .font(Typography.headlineSmall)
                    .foregroundStyle(Color.textPrimary)

                if dailyData(for: selectedPeriod).allSatisfy({ $0.wordCount == 0 }) {
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
            ForEach(dailyData(for: selectedPeriod)) { data in
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
                value: "\(averageWordsPerTranscription(for: selectedPeriod))"
            )
            DetailCard(
                icon: "star.fill",
                label: "Most active day",
                value: mostActiveDay(for: selectedPeriod)
            )
            DetailCard(
                icon: "clock",
                label: "Total duration",
                value: formattedDuration(for: selectedPeriod)
            )
        }
    }

    // MARK: - Data Calculations

    private func dailyData(for period: StatisticsPeriod) -> [DailyWordCount] {
        let calendar = Calendar.current
        let now = Date()

        switch period {
        case .week:
            let startDate = calendar.date(byAdding: .day, value: -6, to: now)!
            return generateDailyData(from: startDate, to: now)

        case .month:
            let startDate = calendar.date(byAdding: .day, value: -29, to: now)!
            return generateDailyData(from: startDate, to: now)

        case .year:
            // For Year view, we aggregate by Month
            let startDate = calendar.date(byAdding: .day, value: -364, to: now)!
            return generateMonthlyData(from: startDate, to: now)
        }
    }

    private func generateDailyData(from startDate: Date, to endDate: Date) -> [DailyWordCount] {
        let calendar = Calendar.current
        var dailyCounts: [Date: Int] = [:]

        for entry in historyService.statsEntries(since: startDate) {
            let day = calendar.startOfDay(for: entry.date)
            dailyCounts[day, default: 0] += entry.wordCount
        }

        var result: [DailyWordCount] = []
        var currentDate = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)

        while currentDate <= end {
            let count = dailyCounts[currentDate] ?? 0
            result.append(DailyWordCount(date: currentDate, wordCount: count, isMonthly: false))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        return result
    }

    private func generateMonthlyData(from startDate: Date, to endDate: Date) -> [DailyWordCount] {
        let calendar = Calendar.current
        var monthlyCounts: [String: Int] = [:]  // Key: "yyyy-MM"

        // Group items by month
        for entry in historyService.statsEntries(since: startDate) {
            let components = calendar.dateComponents([.year, .month], from: entry.date)
            let key = "\(components.year!)-\(components.month!)"
            monthlyCounts[key, default: 0] += entry.wordCount
        }

        // Generate last 12 months buckets
        var result: [DailyWordCount] = []
        var currentDate = calendar.date(
            from: calendar.dateComponents([.year, .month], from: startDate))!
        let end = calendar.date(from: calendar.dateComponents([.year, .month], from: endDate))!

        while currentDate <= end {
            let components = calendar.dateComponents([.year, .month], from: currentDate)
            let key = "\(components.year!)-\(components.month!)"
            let count = monthlyCounts[key] ?? 0

            result.append(DailyWordCount(date: currentDate, wordCount: count, isMonthly: true))

            currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate)!
        }

        return result
    }

    private func totalWords(for period: StatisticsPeriod) -> Int {
        dailyData(for: period).reduce(0) { $0 + $1.wordCount }
    }

    private func dailyAverage(for period: StatisticsPeriod) -> Int {
        let data = dailyData(for: period)
        guard !data.isEmpty else { return 0 }
        return totalWords(for: period) / data.count
    }

    private func bestDay(for period: StatisticsPeriod) -> Int {
        dailyData(for: period).map(\.wordCount).max() ?? 0
    }

    private func transcriptionCount(for period: StatisticsPeriod) -> Int {
        let calendar = Calendar.current
        let now = Date()
        let startDate: Date

        switch period {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -6, to: now)!
        case .month:
            startDate = calendar.date(byAdding: .day, value: -29, to: now)!
        case .year:
            startDate = calendar.date(byAdding: .day, value: -364, to: now)!
        }

        return historyService.transcriptionCount(since: startDate)
    }

    private func formattedDuration(for period: StatisticsPeriod) -> String {
        let calendar = Calendar.current
        let now = Date()
        let startDate: Date

        switch period {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -6, to: now)!
        case .month:
            startDate = calendar.date(byAdding: .day, value: -29, to: now)!
        case .year:
            startDate = calendar.date(byAdding: .day, value: -364, to: now)!
        }

        var totalSeconds = historyService.totalDuration(since: startDate)

        // Add current recording duration if active
        if audioRecorder.isRecording, let recordingStart = audioRecorder.recordingStartTime {
            let currentDuration = timeTrigger.timeIntervalSince(recordingStart)
            // Only add if start date falls within period (usually true for 'now')
            if recordingStart >= startDate {
                totalSeconds += currentDuration
            }
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

    private func averageWordsPerTranscription(for period: StatisticsPeriod) -> Int {
        let count = transcriptionCount(for: period)
        guard count > 0 else { return 0 }
        return totalWords(for: period) / count
    }

    private func mostActiveDay(for period: StatisticsPeriod) -> String {
        let data = dailyData(for: period)
        guard let maxData = data.max(by: { $0.wordCount < $1.wordCount }),
            maxData.wordCount > 0
        else {
            return "N/A"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: maxData.date)
    }
}

// MARK: - Supporting Types

enum StatisticsPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case year = "Year"

    var id: String { rawValue }
}

struct DailyWordCount: Identifiable {
    let id = UUID()
    let date: Date
    let wordCount: Int
    let isMonthly: Bool

    var dateString: String {
        let formatter = DateFormatter()
        if isMonthly {
            formatter.dateFormat = "MMM"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
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
