import DictationCore
import Foundation
import Observation

@MainActor
@Observable
final class RulesManager {
    private let paths: AppPaths

    var personalMarkdown = ""
    var agentMarkdown = ""
    var cleanMarkdown = ""
    var emailMarkdown = ""
    var articleMarkdown = ""
    private(set) var status = ""
    private(set) var errorMessage: String?

    init(paths: AppPaths = .live(bundleIdentifier: AppInfo.bundleIdentifier)) {
        self.paths = paths
        reload()
    }

    var corrections: [PersonalCorrection] {
        PersonalCorrections.parse(personalMarkdown)
    }

    func markdown(for mode: DictationMode) -> String {
        switch mode {
        case .agent: agentMarkdown
        case .clean: cleanMarkdown
        case .email: emailMarkdown
        case .article: articleMarkdown
        case .raw: ""
        }
    }

    func setMarkdown(_ markdown: String, for mode: DictationMode) {
        switch mode {
        case .agent: agentMarkdown = markdown
        case .clean: cleanMarkdown = markdown
        case .email: emailMarkdown = markdown
        case .article: articleMarkdown = markdown
        case .raw: break
        }
    }

    func add(_ correction: PersonalCorrection) {
        personalMarkdown = PersonalCorrections.appending(correction, to: personalMarkdown)
        save()
    }

    func remove(_ correction: PersonalCorrection) {
        personalMarkdown = PersonalCorrections.removing(correction, from: personalMarkdown)
        save()
    }

    func reload() {
        do {
            try paths.createRequiredDirectories()
            personalMarkdown = try loadOrCreate(
                at: personalURL,
                defaultContents: PersonalCorrections.defaultMarkdown
            )
            agentMarkdown = try loadOrCreate(
                at: modeURL(.agent),
                defaultContents: WritingRules.defaultMarkdown(for: .agent)
            )
            cleanMarkdown = try loadOrCreate(
                at: modeURL(.clean),
                defaultContents: WritingRules.defaultMarkdown(for: .clean)
            )
            emailMarkdown = try loadOrCreate(
                at: modeURL(.email),
                defaultContents: WritingRules.defaultMarkdown(for: .email)
            )
            articleMarkdown = try loadOrCreate(
                at: modeURL(.article),
                defaultContents: WritingRules.defaultMarkdown(for: .article),
                replacingLegacyDefault: WritingRules.legacyArticleMarkdownV1
            )
            status = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() {
        do {
            try paths.createRequiredDirectories()
            try Data(personalMarkdown.utf8).write(to: personalURL, options: .atomic)
            try Data(agentMarkdown.utf8).write(to: modeURL(.agent), options: .atomic)
            try Data(cleanMarkdown.utf8).write(to: modeURL(.clean), options: .atomic)
            try Data(emailMarkdown.utf8).write(to: modeURL(.email), options: .atomic)
            try Data(articleMarkdown.utf8).write(to: modeURL(.article), options: .atomic)
            status = "Saved"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var personalURL: URL {
        paths.rules.appendingPathComponent("personal.md")
    }

    private func modeURL(_ mode: DictationMode) -> URL {
        paths.rules.appendingPathComponent("\(mode.rawValue).md")
    }

    private func loadOrCreate(
        at url: URL,
        defaultContents: String,
        replacingLegacyDefault legacyDefault: String? = nil
    ) throws -> String {
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try String(contentsOf: url, encoding: .utf8)
            if let legacyDefault,
               existing.trimmingCharacters(in: .whitespacesAndNewlines)
                == legacyDefault.trimmingCharacters(in: .whitespacesAndNewlines) {
                let migrated = defaultContents + "\n"
                try Data(migrated.utf8).write(to: url, options: .atomic)
                return migrated
            }
            return existing
        }
        try Data((defaultContents + "\n").utf8).write(to: url, options: .atomic)
        return defaultContents + "\n"
    }
}
