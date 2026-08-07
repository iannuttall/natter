import AppKit
import NatterCore
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
    func saveAndCopy(
        _ record: RecoveryRecord,
        copyToClipboard: Bool = true
    ) throws -> URL {
        try paths.createRequiredDirectories()
        let destination = paths.recovery.appendingPathComponent("latest.json")
        try encoder.encode(record).write(to: destination, options: .atomic)

        if copyToClipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(record.clipboardTranscript, forType: .string)
        }
        return destination
    }
}
