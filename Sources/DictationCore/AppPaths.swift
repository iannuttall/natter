import Foundation

public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public static func live(
        fileManager: FileManager = .default,
        bundleIdentifier: String = "is.ian.natter"
    ) -> AppPaths {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return AppPaths(
            root: applicationSupport.appendingPathComponent(
                bundleIdentifier,
                isDirectory: true
            )
        )
    }

    public var models: URL { root.appendingPathComponent("Models", isDirectory: true) }
    public var rules: URL { root.appendingPathComponent("Rules", isDirectory: true) }
    public var recovery: URL { root.appendingPathComponent("Recovery", isDirectory: true) }
    public var profiles: URL { root.appendingPathComponent("Profiles", isDirectory: true) }
    public var history: URL { root.appendingPathComponent("History", isDirectory: true) }

    public func createRequiredDirectories(fileManager: FileManager = .default) throws {
        for directory in [root, models, rules, recovery, profiles, history] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }
}
