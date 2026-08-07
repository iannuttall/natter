import NatterCore
import Foundation

enum LegacyDataMigrator {
    private static let legacyBundleIdentifier = "is.ian.dictation"
    private static let migrationKey = "didMigrateLegacyDictationData"

    static func migrateIfNeeded(
        to bundleIdentifier: String,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) throws {
        guard bundleIdentifier != legacyBundleIdentifier,
              !defaults.bool(forKey: migrationKey) else { return }

        migrateDefaults(to: defaults)

        let legacy = AppPaths.live(
            fileManager: fileManager,
            bundleIdentifier: legacyBundleIdentifier
        )
        let current = AppPaths.live(
            fileManager: fileManager,
            bundleIdentifier: bundleIdentifier
        )
        try LegacyApplicationDataMigration.moveMissingItems(
            from: legacy.root,
            to: current.root,
            fileManager: fileManager
        )
        defaults.set(true, forKey: migrationKey)
    }

    private static func migrateDefaults(to defaults: UserDefaults) {
        guard let legacy = defaults.persistentDomain(
            forName: legacyBundleIdentifier
        ) else { return }
        for (key, value) in legacy where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
