import Foundation

public enum DictationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case raw
    case agent
    case clean
    case email
    case article

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .raw: "Raw"
        case .agent: "Agent"
        case .clean: "Clean"
        case .email: "Email"
        case .article: "Article"
        }
    }

    public var detail: String {
        switch self {
        case .raw:
            "Fast live dictation with personal corrections only."
        case .agent:
            "Live dictation that preserves code, paths, constraints and line breaks."
        case .clean:
            "Remove filler and resolve false starts after you stop."
        case .email:
            "Turn the finished transcript into a direct, natural email."
        case .article:
            "Restructure the finished transcript using your writing rules."
        }
    }

    public var isGenerative: Bool {
        switch self {
        case .raw, .agent: false
        case .clean, .email, .article: true
        }
    }

    public var typesIncrementally: Bool {
        !isGenerative
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
