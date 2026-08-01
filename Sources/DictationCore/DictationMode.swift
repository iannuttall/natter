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
            "Format technical dictation after you stop, then type it visibly."
        case .clean:
            "Remove filler and obvious repeated words after you stop."
        case .email:
            "Turn the finished transcript into a direct, natural email."
        case .article:
            "Restructure the finished transcript using your writing rules."
        }
    }

    public var isGenerative: Bool {
        switch self {
        case .raw, .agent, .clean: false
        case .email, .article: true
        }
    }

    public var typesIncrementally: Bool {
        switch self {
        case .raw: true
        case .agent, .clean, .email, .article: false
        }
    }

    public var next: Self {
        let modes = Self.allCases
        guard let index = modes.firstIndex(of: self) else { return .raw }
        return modes[modes.index(after: index) % modes.count]
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
