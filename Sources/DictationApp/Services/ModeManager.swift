import DictationCore
import Foundation
import Observation

@MainActor
@Observable
final class ModeManager {
    private(set) var modes: [ModeDefinition]
    private(set) var status = ""
    private(set) var errorMessage: String?

    private let fileURL: URL
    private let paths: AppPaths
    private let fileManager: FileManager

    init(
        paths: AppPaths = .live(bundleIdentifier: AppInfo.bundleIdentifier),
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard
    ) {
        self.paths = paths
        self.fileManager = fileManager
        fileURL = paths.profiles.appendingPathComponent("modes.json")

        if let loaded = Self.load(from: fileURL) {
            modes = Self.normalized(loaded.modes)
        } else {
            modes = Self.migratedDefaults(
                paths: paths,
                fileManager: fileManager,
                defaults: defaults
            )
            save()
        }
    }

    var enabledModes: [ModeDefinition] {
        modes.filter { $0.isRaw || $0.isEnabled }
    }

    var configurableModes: [ModeDefinition] {
        modes.filter { !$0.isRaw }
    }

    func definition(for id: DictationMode) -> ModeDefinition {
        modes.first { $0.id == id }
            ?? Self.defaultDefinitions.first { $0.id == id }
            ?? ModeDefinition(
                id: id,
                name: id.label,
                processing: .fast,
                instructions: WritingRules.defaultMarkdown(for: id)
            )
    }

    func enabledDefinition(for id: DictationMode) -> ModeDefinition? {
        enabledModes.first { $0.id == id }
    }

    func name(for id: DictationMode) -> String {
        let definition = definition(for: id)
        let name = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? id.label : name
    }

    func update(_ definition: ModeDefinition) {
        guard let index = modes.firstIndex(where: { $0.id == definition.id }) else { return }
        modes[index] = normalized(definition)
        save()
    }

    @discardableResult
    func addMode(copying source: ModeDefinition? = nil) -> ModeDefinition {
        let id = DictationMode(rawValue: "custom-\(UUID().uuidString.lowercased())")!
        let definition = ModeDefinition(
            id: id,
            name: uniqueName(source.map { "\(name(for: $0.id)) Copy" } ?? "New Mode"),
            processing: source?.processing ?? .fast,
            instructions: source?.instructions ?? WritingRules.customModeMarkdown,
            removesFalseStarts: source?.removesFalseStarts ?? false
        )
        modes.append(definition)
        save()
        return definition
    }

    func setEnabled(_ enabled: Bool, for id: DictationMode) {
        guard id != .raw,
              let index = modes.firstIndex(where: { $0.id == id }) else { return }
        modes[index].isEnabled = enabled
        save()
    }

    func delete(_ id: DictationMode) {
        guard let definition = modes.first(where: { $0.id == id }),
              !definition.isRaw,
              !definition.isBuiltIn else { return }
        modes.removeAll { $0.id == id }
        save()
    }

    func move(_ id: DictationMode, by offset: Int) {
        guard id != .raw,
              let index = modes.firstIndex(where: { $0.id == id }) else { return }
        let visibleIndexes = modes.indices.filter {
            !modes[$0].isRaw && modes[$0].isEnabled
        }
        guard let position = visibleIndexes.firstIndex(of: index) else { return }
        let destinationPosition = position + offset
        guard visibleIndexes.indices.contains(destinationPosition) else { return }
        let definition = modes.remove(at: index)
        let destination = visibleIndexes[destinationPosition]
        modes.insert(definition, at: destination)
        save()
    }

    func resetBuiltIn(_ id: DictationMode) {
        guard let replacement = Self.defaultDefinitions.first(where: { $0.id == id }),
              let index = modes.firstIndex(where: { $0.id == id }) else { return }
        let wasEnabled = modes[index].isEnabled
        modes[index] = ModeDefinition(
            id: replacement.id,
            name: replacement.name,
            processing: replacement.processing,
            instructions: replacement.instructions,
            removesFalseStarts: replacement.removesFalseStarts,
            isEnabled: wasEnabled,
            isBuiltIn: true
        )
        save()
    }

    func reload() {
        guard let loaded = Self.load(from: fileURL) else { return }
        modes = Self.normalized(loaded.modes)
        status = "Reloaded"
        errorMessage = nil
    }

    private func normalized(_ definition: ModeDefinition) -> ModeDefinition {
        if definition.isRaw {
            return Self.defaultDefinitions[0]
        }
        return ModeDefinition(
            id: definition.id,
            name: String(definition.name.prefix(40)),
            processing: definition.processing,
            instructions: definition.instructions,
            removesFalseStarts: definition.removesFalseStarts,
            isEnabled: definition.isEnabled,
            isBuiltIn: definition.isBuiltIn
        )
    }

    private func uniqueName(_ proposed: String) -> String {
        let names = Set(modes.map { $0.name.lowercased() })
        guard names.contains(proposed.lowercased()) else { return proposed }
        var counter = 2
        while names.contains("\(proposed) \(counter)".lowercased()) { counter += 1 }
        return "\(proposed) \(counter)"
    }

    private func save() {
        do {
            try paths.createRequiredDirectories()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(ModeConfiguration(modes: modes))
                .write(to: fileURL, options: .atomic)
            status = "Saved"
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t save modes: \(error.localizedDescription)"
        }
    }

    private static func load(from url: URL) -> ModeConfiguration? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ModeConfiguration.self, from: data)
    }

    private static func normalized(_ loaded: [ModeDefinition]) -> [ModeDefinition] {
        var seen: Set<DictationMode> = []
        var result: [ModeDefinition] = []
        for existing in loaded where existing.id != .raw && seen.insert(existing.id).inserted {
            let builtIn = defaultDefinitions.first { $0.id == existing.id }
            let trimmedName = existing.name.trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(ModeDefinition(
                id: existing.id,
                name: trimmedName.isEmpty ? (builtIn?.name ?? existing.id.label) : trimmedName,
                processing: existing.processing,
                instructions: existing.instructions,
                removesFalseStarts: existing.removesFalseStarts,
                isEnabled: existing.isEnabled,
                isBuiltIn: builtIn != nil
            ))
        }
        for missing in defaultDefinitions where missing.id != .raw && !seen.contains(missing.id) {
            result.append(missing)
        }
        return [defaultDefinitions[0]] + result
    }

    private static func migratedDefaults(
        paths: AppPaths,
        fileManager: FileManager,
        defaults: UserDefaults
    ) -> [ModeDefinition] {
        defaultDefinitions.map { definition in
            guard !definition.isRaw else { return definition }
            let legacyURL = paths.rules.appendingPathComponent("\(definition.id.rawValue).md")
            var migrated = definition
            if fileManager.fileExists(atPath: legacyURL.path),
               let markdown = try? String(contentsOf: legacyURL, encoding: .utf8),
               !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                migrated.instructions = markdown
            }
            if definition.id == .clean {
                let enabled = defaults.object(forKey: "smartCleanEnabled") as? Bool
                    ?? defaults.object(forKey: "smartAgentEnabled") as? Bool
                    ?? true
                migrated.processing = enabled ? .refine : .fast
                migrated.removesFalseStarts = defaults.object(
                    forKey: "cleanRemovesFalseStarts"
                ) as? Bool
                    ?? defaults.object(forKey: "agentRemovesFalseStarts") as? Bool
                    ?? false
            }
            return migrated
        }
    }

    private static let defaultDefinitions: [ModeDefinition] = [
        ModeDefinition(
            id: .raw,
            name: "Raw",
            processing: .fast,
            instructions: "",
            isBuiltIn: true
        ),
        ModeDefinition(
            id: .agent,
            name: "Agent",
            processing: .fast,
            instructions: WritingRules.defaultMarkdown(for: .agent),
            isBuiltIn: true
        ),
        ModeDefinition(
            id: .clean,
            name: "Clean",
            processing: .refine,
            instructions: WritingRules.defaultMarkdown(for: .clean),
            isBuiltIn: true
        ),
        ModeDefinition(
            id: .email,
            name: "Email",
            processing: .rewrite,
            instructions: WritingRules.defaultMarkdown(for: .email),
            isBuiltIn: true
        ),
        ModeDefinition(
            id: .article,
            name: "Article",
            processing: .rewrite,
            instructions: WritingRules.defaultMarkdown(for: .article),
            isBuiltIn: true
        )
    ]
}
