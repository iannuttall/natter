import AppKit
import NatterCore
import Foundation
import Observation

struct InstalledApplication: Identifiable, Hashable, Sendable {
    let bundleIdentifier: String
    let displayName: String
    let url: URL

    var id: String { bundleIdentifier }
}

@MainActor
@Observable
final class ApplicationProfileManager {
    private(set) var configuration: ApplicationModeConfiguration
    private(set) var installedApplications: [InstalledApplication] = []
    private(set) var errorMessage: String?

    private let fileURL: URL
    private let fileManager: FileManager

    init(
        paths: AppPaths = .live(bundleIdentifier: AppInfo.bundleIdentifier),
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        fileURL = paths.profiles.appendingPathComponent("app-modes.json")
        configuration = Self.load(from: fileURL) ?? ApplicationModeConfiguration()
    }

    var isEnabled: Bool {
        get { configuration.enabled }
        set {
            configuration.enabled = newValue
            save()
        }
    }

    func mode(for group: ApplicationGroup) -> DictationMode? {
        configuration.groupModes[group]
    }

    func setMode(_ mode: DictationMode?, for group: ApplicationGroup) {
        configuration.groupModes[group] = mode
        save()
    }

    func setMode(_ mode: DictationMode, for application: InstalledApplication) {
        let profile = ApplicationModeProfile(
            bundleIdentifier: application.bundleIdentifier,
            displayName: application.displayName,
            mode: mode
        )
        if let index = configuration.applications.firstIndex(where: {
            $0.bundleIdentifier.caseInsensitiveCompare(application.bundleIdentifier) == .orderedSame
        }) {
            configuration.applications[index] = profile
        } else {
            configuration.applications.append(profile)
            configuration.applications.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
        save()
    }

    func remove(bundleIdentifier: String) {
        configuration.applications.removeAll {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }
        save()
    }

    func resolution(
        bundleIdentifier: String?,
        defaultMode: DictationMode
    ) -> ModeResolution {
        configuration.resolve(
            bundleIdentifier: bundleIdentifier,
            defaultMode: defaultMode
        )
    }

    func application(at url: URL) -> InstalledApplication? {
        Self.application(at: url)
    }

    func refreshInstalledApplications() {
        Task.detached(priority: .utility) {
            let applications = Self.findApplications()
            await MainActor.run {
                self.installedApplications = applications
            }
        }
    }

    private func save() {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: fileURL, options: .atomic)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t save app modes: \(error.localizedDescription)"
        }
    }

    private static func load(from url: URL) -> ApplicationModeConfiguration? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ApplicationModeConfiguration.self, from: data)
    }

    nonisolated private static func findApplications() -> [InstalledApplication] {
        let fileManager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
        var byIdentifier: [String: InstalledApplication] = [:]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension == "app" {
                guard let application = application(at: url) else { continue }
                byIdentifier[application.bundleIdentifier.lowercased()] = application
            }
        }

        return byIdentifier.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    nonisolated private static func application(at url: URL) -> InstalledApplication? {
        guard let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier else { return nil }
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApplication(
            bundleIdentifier: identifier,
            displayName: displayName,
            url: url
        )
    }
}
