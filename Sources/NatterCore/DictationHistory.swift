import Foundation

public enum DictationOutcome: String, Codable, Sendable {
    case delivered
    case recovered
    case cancelled
}

public struct DictationHistoryRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let durationSeconds: TimeInterval
    public let mode: DictationMode
    public let modeName: String?
    public let wordCount: Int
    public let sourceBundleIdentifier: String?
    public let sourceApplicationName: String?
    public var transcript: String?
    public var rawTranscript: String?
    public let outcome: DictationOutcome

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        durationSeconds: TimeInterval,
        mode: DictationMode,
        modeName: String? = nil,
        wordCount: Int,
        sourceBundleIdentifier: String?,
        sourceApplicationName: String?,
        transcript: String?,
        rawTranscript: String? = nil,
        outcome: DictationOutcome
    ) {
        self.id = id
        self.createdAt = createdAt
        self.durationSeconds = max(0, durationSeconds)
        self.mode = mode
        self.modeName = modeName
        self.wordCount = max(0, wordCount)
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceApplicationName = sourceApplicationName
        self.transcript = transcript
        self.rawTranscript = rawTranscript
        self.outcome = outcome
    }

    public static func countWords(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}

public struct DictationSourceStatistic: Equatable, Identifiable, Sendable {
    public let bundleIdentifier: String?
    public let applicationName: String
    public let wordCount: Int

    public var id: String { bundleIdentifier ?? applicationName }
}

public struct DictationActivityDay: Equatable, Identifiable, Sendable {
    public let date: Date
    public let count: Int

    public var id: Date { date }

    public init(date: Date, count: Int) {
        self.date = date
        self.count = max(0, count)
    }
}

public enum DictationActivity {
    public static func recentDays(
        records: [DictationHistoryRecord],
        dayCount: Int = 35,
        through date: Date = Date(),
        calendar: Calendar = .current
    ) -> [DictationActivityDay] {
        guard dayCount > 0 else { return [] }
        let lastDay = calendar.startOfDay(for: date)
        guard let firstDay = calendar.date(
            byAdding: .day,
            value: -(dayCount - 1),
            to: lastDay
        ) else { return [] }

        var counts: [Date: Int] = [:]
        for record in records {
            let recordDay = calendar.startOfDay(for: record.createdAt)
            guard recordDay >= firstDay, recordDay <= lastDay else { continue }
            counts[recordDay, default: 0] += 1
        }

        return (0..<dayCount).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return nil
            }
            return DictationActivityDay(date: day, count: counts[day, default: 0])
        }
    }
}

public struct DictationStatistics: Equatable, Sendable {
    public let totalWords: Int
    public let totalDurationSeconds: TimeInterval
    public let estimatedTimeSavedSeconds: TimeInterval
    public let averageWordsPerMinute: Double
    public let activeDayCount: Int
    public let topSources: [DictationSourceStatistic]

    public init(
        records: [DictationHistoryRecord],
        since cutoff: Date? = nil,
        typingWordsPerMinute: Double = 40,
        calendar: Calendar = .current
    ) {
        let included = cutoff.map { cutoff in
            records.filter { $0.createdAt >= cutoff }
        } ?? records
        totalWords = included.reduce(0) { $0 + $1.wordCount }
        totalDurationSeconds = included.reduce(0) { $0 + $1.durationSeconds }
        averageWordsPerMinute = totalDurationSeconds > 0
            ? Double(totalWords) / (totalDurationSeconds / 60)
            : 0
        let safeTypingRate = max(1, typingWordsPerMinute)
        estimatedTimeSavedSeconds = included.reduce(0) { result, record in
            let estimatedTypingSeconds = Double(record.wordCount) / safeTypingRate * 60
            return result + max(0, estimatedTypingSeconds - record.durationSeconds)
        }
        activeDayCount = Set(included.map {
            calendar.startOfDay(for: $0.createdAt)
        }).count

        struct SourceKey: Hashable {
            let bundleIdentifier: String?
            let applicationName: String
        }
        let grouped = Dictionary(grouping: included) { record in
            SourceKey(
                bundleIdentifier: record.sourceBundleIdentifier,
                applicationName: record.sourceApplicationName ?? "Unknown app"
            )
        }
        topSources = grouped.map { key, records in
            DictationSourceStatistic(
                bundleIdentifier: key.bundleIdentifier,
                applicationName: key.applicationName,
                wordCount: records.reduce(0) { $0 + $1.wordCount }
            )
        }
        .sorted {
            if $0.wordCount == $1.wordCount {
                $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName)
                    == .orderedAscending
            } else {
                $0.wordCount > $1.wordCount
            }
        }
    }
}
