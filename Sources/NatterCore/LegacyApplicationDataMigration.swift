import Foundation

public enum LegacyApplicationDataMigration {
    public static func moveMissingItems(
        from source: URL,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        for item in try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil
        ) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            try fileManager.moveItem(at: item, to: target)
        }
    }
}
