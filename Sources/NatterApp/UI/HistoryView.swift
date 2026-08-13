import AppKit
import NatterCore
import SwiftUI

struct HistoryView: View {
    @Bindable var history: HistoryManager
    @State private var range: StatisticsRange = .lifetime
    @State private var confirmingClear = false

    var body: some View {
        let dashboard = HistoryDashboard(history: history, range: range)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                metrics(dashboard.statistics)
                HStack(alignment: .top, spacing: 24) {
                    topSources(dashboard.statistics.topSources)
                    activity(dashboard.activityDays)
                }
                recent(dashboard.visibleRecords)
            }
            .padding(24)
        }
        .background(Theme.Colour.panel)
        .alert("Clear all local history?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) { history.clear() }
        } message: {
            Text("This permanently removes transcripts and lifetime statistics from this Mac.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your dictation")
                    .font(.system(size: 26, weight: .semibold))
                Text("Stored only on this Mac.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Range", selection: $range) {
                ForEach(StatisticsRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .labelsHidden()
            .frame(width: 130)
        }
    }

    private func metrics(_ statistics: DictationStatistics) -> some View {
        HStack(spacing: 1) {
            metric("Total words", value: statistics.totalWords.formatted())
            Divider()
            metric(
                "Time saved",
                value: durationLabel(statistics.estimatedTimeSavedSeconds)
            )
            Divider()
            metric(
                "Average WPM",
                value: String(Int(statistics.averageWordsPerMinute.rounded()))
            )
            Divider()
            metric("Active days", value: statistics.activeDayCount.formatted())
        }
        .padding(.vertical, 18)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func topSources(_ sources: [DictationSourceStatistic]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top apps")
                .font(.title3.weight(.semibold))
            VStack(spacing: 0) {
                if sources.isEmpty {
                    emptyState("Your destination apps will appear here.")
                } else {
                    ForEach(Array(sources.prefix(5).enumerated()), id: \.element.id) {
                        index, source in
                        HStack(spacing: 10) {
                            applicationIcon(bundleIdentifier: source.bundleIdentifier)
                            Text(source.applicationName)
                                .lineLimit(1)
                            Spacer()
                            Text("\(source.wordCount.formatted()) words")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        if index < min(4, sources.count - 1) { Divider() }
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.Colour.secondaryPanel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func activity(_ days: [DictationActivityDay]) -> some View {
        let maximum = max(1, days.map(\.count).max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Last 35 days")
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 7), count: 7), spacing: 7) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colour.accent.opacity(dayOpacity(day.count, maximum: maximum)))
                        .frame(width: 18, height: 18)
                        .help("\(day.date.formatted(date: .abbreviated, time: .omitted)): \(day.count) dictations")
                }
            }
            Text("\(days.count { $0.count > 0 }) active days")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func recent(_ records: [DictationHistoryRecord]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent dictations")
                    .font(.title3.weight(.semibold))
                Spacer()
                if !history.records.isEmpty {
                    Button("Clear…", role: .destructive) { confirmingClear = true }
                }
            }

            if records.isEmpty {
                emptyState("Completed dictations will appear here.")
                    .frame(maxWidth: .infinity)
                    .background(Theme.Colour.secondaryPanel)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(records) { record in
                        recordRow(record)
                    }
                }
            }
        }
    }

    private func recordRow(_ record: DictationHistoryRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            applicationIcon(bundleIdentifier: record.sourceBundleIdentifier)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(record.sourceApplicationName ?? "Unknown app")
                        .fontWeight(.medium)
                    Text(record.modeName ?? record.mode.label)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Colour.accent.opacity(0.16))
                        .clipShape(Capsule())
                    if record.outcome != .delivered {
                        Text(record.outcome == .cancelled ? "Cancelled" : "Recovered")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                if let transcript = record.transcript {
                    Text(transcript)
                        .lineLimit(3)
                        .textSelection(.enabled)
                } else {
                    Text("Transcript text was not stored.")
                        .foregroundStyle(.tertiary)
                        .italic()
                }
                Text("\(record.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(record.wordCount) words · \(durationLabel(record.durationSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let transcript = record.transcript {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy transcript")
            }
        }
        .padding(14)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func dayOpacity(_ count: Int, maximum: Int) -> Double {
        guard count > 0 else { return 0.08 }
        return 0.3 + 0.7 * Double(count) / Double(maximum)
    }

    private func applicationIcon(bundleIdentifier: String?) -> some View {
        let image: NSImage
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(
               withBundleIdentifier: bundleIdentifier
           ) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        }
        return Image(nsImage: image)
            .resizable()
            .frame(width: 28, height: 28)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(20)
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let rounded = Int(seconds.rounded())
        if rounded >= 3600 { return "\(rounded / 3600)h \((rounded % 3600) / 60)m" }
        if rounded >= 60 { return "\(rounded / 60)m" }
        return "\(rounded)s"
    }
}

private struct HistoryDashboard {
    let statistics: DictationStatistics
    let visibleRecords: [DictationHistoryRecord]
    let activityDays: [DictationActivityDay]

    @MainActor
    init(history: HistoryManager, range: StatisticsRange, now: Date = Date()) {
        statistics = history.statistics(for: range)
        let cutoff = range.cutoff(from: now)
        visibleRecords = Array(
            history.recentRecords.lazy
                .filter { record in cutoff.map { record.createdAt >= $0 } ?? true }
                .prefix(50)
        )
        activityDays = DictationActivity.recentDays(
            records: history.records,
            through: now
        )
    }
}
