import AppKit
import DictationCore
import Foundation

@MainActor
final class TranscriptRecovery {
    private let paths: AppPaths
    private let encoder: JSONEncoder

    init(paths: AppPaths = .live(bundleIdentifier: AppInfo.bundleIdentifier)) {
        self.paths = paths
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    @discardableResult
    func saveAndCopy(_ record: RecoveryRecord) throws -> URL {
        try paths.createRequiredDirectories()
        let destination = paths.recovery.appendingPathComponent("latest.json")
        try encoder.encode(record).write(to: destination, options: .atomic)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.transcript, forType: .string)
        return destination
    }
}
