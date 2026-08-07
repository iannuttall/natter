import DictationCore
import Foundation
import Observation

enum HistoryStorageMode: String, CaseIterable, Identifiable {
    case full
    case statisticsOnly
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: "Transcripts and stats"
        case .statisticsOnly: "Stats only"
        case .off: "Off"
        }
    }
}

enum TranscriptRetention: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90
    case oneYear = 365
    case forever = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .ninetyDays: "90 days"
        case .oneYear: "1 year"
        case .forever: "Forever"
        }
    }
}

enum StatisticsRange: String, CaseIterable, Identifiable {
    case sevenDays
    case thirtyDays
    case year
    case lifetime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .year: "1 year"
        case .lifetime: "Lifetime"
        }
    }

    func cutoff(from date: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .sevenDays: calendar.date(byAdding: .day, value: -7, to: date)
        case .thirtyDays: calendar.date(byAdding: .day, value: -30, to: date)
        case .year: calendar.date(byAdding: .year, value: -1, to: date)
        case .lifetime: nil
        }
    }
}

@MainActor
@Observable
final class HistoryManager {
    private(set) var records: [DictationHistoryRecord]
    private(set) var errorMessage: String?

    var storageMode: HistoryStorageMode {
        didSet {
            defaults.set(storageMode.rawValue, forKey: Keys.storageMode)
            if storageMode != .full { removeStoredTranscripts() }
        }
    }

    var retention: TranscriptRetention {
        didSet {
            defaults.set(retention.rawValue, forKey: Keys.retention)
            applyRetention()
        }
    }

    var typingWordsPerMinute: Double {
        didSet {
            typingWordsPerMinute = min(200, max(10, typingWordsPerMinute))
            defaults.set(typingWordsPerMinute, forKey: Keys.typingWordsPerMinute)
        }
    }

    private let fileURL: URL
    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(
        paths: AppPaths = .live(bundleIdentifier: AppInfo.bundleIdentifier),
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        fileURL = paths.history.appendingPathComponent("dictations.json")
        records = Self.load(from: fileURL)
        storageMode = defaults.string(forKey: Keys.storageMode)
            .flatMap(HistoryStorageMode.init(rawValue:))
            ?? .full
        retention = TranscriptRetention(
            rawValue: defaults.object(forKey: Keys.retention) as? Int ?? 90
        ) ?? .ninetyDays
        let savedTypingRate = defaults.double(forKey: Keys.typingWordsPerMinute)
        typingWordsPerMinute = savedTypingRate > 0 ? savedTypingRate : 40
        applyRetention()
    }

    var recentRecords: [DictationHistoryRecord] {
        Array(records.prefix(100))
    }

    func statistics(for range: StatisticsRange) -> DictationStatistics {
        DictationStatistics(
            records: records,
            since: range.cutoff(),
            typingWordsPerMinute: typingWordsPerMinute
        )
    }

    func record(
        transcript: String,
        rawTranscript: String,
        durationSeconds: TimeInterval,
        mode: DictationMode,
        modeName: String? = nil,
        sourceBundleIdentifier: String?,
        sourceApplicationName: String?,
        outcome: DictationOutcome
    ) {
        guard storageMode != .off else { return }
        let record = DictationHistoryRecord(
            durationSeconds: durationSeconds,
            mode: mode,
            modeName: modeName,
            wordCount: DictationHistoryRecord.countWords(in: transcript),
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceApplicationName: sourceApplicationName,
            transcript: storageMode == .full ? transcript : nil,
            rawTranscript: storageMode == .full ? rawTranscript : nil,
            outcome: outcome
        )
        records.insert(record, at: 0)
        save()
    }

    func clear() {
        records = []
        save()
    }

    private func applyRetention(now: Date = Date()) {
        guard retention != .forever else { return }
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retention.rawValue,
            to: now
        ) ?? now
        var changed = false
        for index in records.indices where records[index].createdAt < cutoff {
            if records[index].transcript != nil {
                records[index].transcript = nil
                changed = true
            }
            if records[index].rawTranscript != nil {
                records[index].rawTranscript = nil
                changed = true
            }
        }
        if changed { save() }
    }

    private func removeStoredTranscripts() {
        var changed = false
        for index in records.indices where records[index].transcript != nil {
            records[index].transcript = nil
            changed = true
        }
        for index in records.indices where records[index].rawTranscript != nil {
            records[index].rawTranscript = nil
            changed = true
        }
        if changed { save() }
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(HistoryArchive(records: records))
                .write(to: fileURL, options: .atomic)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t save local history: \(error.localizedDescription)"
        }
    }

    private static func load(from url: URL) -> [DictationHistoryRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let archive = try? decoder.decode(HistoryArchive.self, from: data) {
            return archive.records.sorted { $0.createdAt > $1.createdAt }
        }
        return ((try? decoder.decode([DictationHistoryRecord].self, from: data)) ?? [])
            .sorted { $0.createdAt > $1.createdAt }
    }

    private enum Keys {
        static let storageMode = "historyStorageMode"
        static let retention = "transcriptRetentionDays"
        static let typingWordsPerMinute = "typingWordsPerMinute"
    }
}

private struct HistoryArchive: Codable {
    let schemaVersion: Int
    let records: [DictationHistoryRecord]

    init(schemaVersion: Int = 1, records: [DictationHistoryRecord]) {
        self.schemaVersion = schemaVersion
        self.records = records
    }
}
