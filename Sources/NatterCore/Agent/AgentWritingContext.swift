import Foundation

public struct TranscriptTerminology: Codable, Equatable, Sendable {
    public let preferred: String
    public let variants: [String]
    public let authoritative: Bool?

    public init(
        preferred: String,
        variants: [String] = [],
        authoritative: Bool = false
    ) {
        self.preferred = preferred
        self.variants = variants
        self.authoritative = authoritative
    }
}

public struct AgentWritingContext: Equatable, Sendable {
    public let destinationApplicationName: String?
    public let terminology: [TranscriptTerminology]
    /// Opt-in: lets the model delete abandoned false starts ("what am I—")
    /// from segments that contain a spoken-aside cue. Deletion-only — the
    /// wording guard still rejects any added or reordered word.
    public let removesFalseStarts: Bool

    public init(
        destinationApplicationName: String? = nil,
        terminology: [TranscriptTerminology] = [],
        removesFalseStarts: Bool = false
    ) {
        self.destinationApplicationName = destinationApplicationName
        self.terminology = terminology
        self.removesFalseStarts = removesFalseStarts
    }

    public static func production(
        destinationApplicationName: String?,
        corrections: [PersonalCorrection],
        removesFalseStarts: Bool = false
    ) -> AgentWritingContext {
        var terms = builtInTerminology
        terms.append(
            contentsOf: corrections.map {
                TranscriptTerminology(
                    preferred: $0.replacement,
                    variants: [$0.heard],
                    authoritative: true
                )
            })

        var seen: Set<String> = []
        terms = terms.filter { term in
            let key = term.preferred.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return false }
            return true
        }
        return AgentWritingContext(
            destinationApplicationName: destinationApplicationName,
            terminology: terms,
            removesFalseStarts: removesFalseStarts
        )
    }

    public var promptSection: String {
        promptSection(relevantTo: nil)
    }

    public func promptSection(relevantTo transcript: String?) -> String {
        var lines: [String] = []
        if let destinationApplicationName,
            !destinationApplicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            lines.append("Destination application: \(destinationApplicationName)")
        }
        let spellings =
            if let transcript {
                protectedSpellings.filter { transcript.localizedCaseInsensitiveContains($0) }
            } else {
                protectedSpellings
            }
        if !spellings.isEmpty {
            lines.append(
                "Protected terminology already handled by deterministic rules (never use any exact listed form as an edit source):"
            )
            lines.append("- " + spellings.prefix(64).joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    public var protectedSpellings: [String] {
        var seen: Set<String> = []
        return terminology.flatMap { [$0.preferred] + $0.variants }.filter { spelling in
            let key = spelling
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    private static let builtInTerminology = [
        TranscriptTerminology(preferred: "Natter", variants: ["Nata", "NATA"]),
        TranscriptTerminology(preferred: "GitHub", variants: ["Gitter"]),
        TranscriptTerminology(preferred: "ChatGPT"),
        TranscriptTerminology(preferred: "ChatGPT Desktop"),
        TranscriptTerminology(preferred: "Claude"),
        TranscriptTerminology(preferred: "Claude Desktop"),
        TranscriptTerminology(preferred: "SwiftPM"),
        TranscriptTerminology(preferred: "MLX"),
        TranscriptTerminology(preferred: "FluidAudio"),
        TranscriptTerminology(preferred: "Qwen"),
        TranscriptTerminology(preferred: "Nemotron"),
        TranscriptTerminology(preferred: "Parakeet"),
        TranscriptTerminology(preferred: "Monologue"),
        TranscriptTerminology(preferred: "Keep"),
        TranscriptTerminology(preferred: "Tauri", variants: ["Tori", "Torii"]),
        TranscriptTerminology(preferred: "hreflang", variants: ["Href lang", "HRF Lang"]),
    ]
}
