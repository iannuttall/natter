import Foundation

public struct DictationMode: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    public let rawValue: String

    public var id: String { rawValue }

    public init?(rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty,
              value.range(of: #"^[a-z0-9][a-z0-9-]{0,63}$"#, options: .regularExpression)
                != nil else {
            return nil
        }
        self.rawValue = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let mode = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid dictation mode identifier"
            )
        }
        self = mode
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let raw = Self(rawValue: "raw")!
    public static let agent = Self(rawValue: "agent")!
    public static let clean = Self(rawValue: "clean")!
    public static let email = Self(rawValue: "email")!
    public static let article = Self(rawValue: "article")!

    /// The original identifiers remain stable for history, app profiles and URLs.
    public static let allCases: [Self] = [.raw, .agent, .clean, .email, .article]

    public var label: String {
        switch self {
        case .raw: "Raw"
        case .agent: "Agent"
        case .clean: "Clean"
        case .email: "Email"
        case .article: "Article"
        default: rawValue.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        }
    }

    public var detail: String {
        switch self {
        case .raw: "Direct Parakeet dictation with the Natter name fixed. Fastest, with no cleanup."
        case .agent: "Fast deterministic formatting for code, commands and technical terms."
        case .clean: "Deterministic cleanup, plus optional local sentence polishing."
        case .email: "Turn the finished transcript into a direct, natural email."
        case .article: "Restructure the finished transcript using your writing rules."
        default: "A custom local dictation mode."
        }
    }

    /// Kept for compatibility with existing benchmark and history code.
    public var isGenerative: Bool { self == .email || self == .article }

    public var typesIncrementally: Bool { false }

    public var defaultProcessing: ModeProcessing {
        switch self {
        case .clean: .refine
        case .email, .article: .rewrite
        default: .fast
        }
    }

    public var next: Self {
        guard let index = Self.allCases.firstIndex(of: self) else { return .raw }
        return Self.allCases[Self.allCases.index(after: index) % Self.allCases.count]
    }
}

public enum ModeProcessing: String, Codable, CaseIterable, Identifiable, Sendable {
    case fast
    case refine
    case rewrite

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fast: "Fast"
        case .refine: "Refine"
        case .rewrite: "Rewrite"
        }
    }

    public var detail: String {
        switch self {
        case .fast:
            "Uses deterministic cleanup only."
        case .refine:
            "Improves punctuation and flow while preserving your words; falls back to Fast when unavailable."
        case .rewrite:
            "Restructures the transcript using this mode’s instructions."
        }
    }
}

public struct ModeDefinition: Codable, Equatable, Identifiable, Sendable {
    public let id: DictationMode
    public var name: String
    public var processing: ModeProcessing
    public var instructions: String
    public var removesFalseStarts: Bool
    public var isEnabled: Bool
    public let isBuiltIn: Bool

    public init(
        id: DictationMode,
        name: String,
        processing: ModeProcessing,
        instructions: String,
        removesFalseStarts: Bool = false,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.processing = processing
        self.instructions = instructions
        self.removesFalseStarts = removesFalseStarts
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }

    public var isRaw: Bool { id == .raw }
}

public struct ModeConfiguration: Codable, Equatable, Sendable {
    public var modes: [ModeDefinition]

    public init(modes: [ModeDefinition]) {
        self.modes = modes
    }
}

public enum DictationPhase: Equatable, Sendable {
    case idle
    case preparing
    case listening
    case finalizing
    case transforming
    case recoverable(String)
    case failed(String)

    public var isBusy: Bool {
        switch self {
        case .preparing, .listening, .finalizing, .transforming: true
        case .idle, .recoverable, .failed: false
        }
    }

    public var canStartSession: Bool {
        switch self {
        case .idle, .recoverable, .failed: true
        case .preparing, .listening, .finalizing, .transforming: false
        }
    }

    public var label: String {
        switch self {
        case .idle: "Ready"
        case .preparing: "Preparing"
        case .listening: "Listening"
        case .finalizing: "Finishing"
        case .transforming: "Writing"
        case .recoverable: "Transcript saved"
        case .failed: "Needs attention"
        }
    }
}
