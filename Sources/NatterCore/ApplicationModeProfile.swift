import Foundation

public enum ApplicationGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case terminal
    case mail
    case writing

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .terminal: "Terminals"
        case .mail: "Mail apps"
        case .writing: "Writing apps"
        }
    }

    public var detail: String {
        switch self {
        case .terminal: "Terminal, Ghostty, iTerm, Warp and other terminal apps."
        case .mail: "Apple Mail, Outlook, Mimestream and other mail clients."
        case .writing: "Markdown editors and long-form writing apps."
        }
    }

    public static func classify(bundleIdentifier: String?) -> Self? {
        guard let identifier = bundleIdentifier?.lowercased() else { return nil }
        if DestinationApplicationKind.classify(bundleIdentifier: identifier) == .terminal {
            return .terminal
        }
        if mailBundleIdentifiers.contains(identifier) { return .mail }
        if writingBundleIdentifiers.contains(identifier) { return .writing }
        return nil
    }

    private static let mailBundleIdentifiers: Set<String> = [
        "com.apple.mail",
        "com.microsoft.outlook",
        "com.mimestream.mimestream",
        "com.readdle.smartemail-mac",
        "com.freron.mailmate"
    ]

    private static let writingBundleIdentifiers: Set<String> = [
        "com.bear-writer.bear",
        "com.craftdocs.craft",
        "com.iawriter.mac",
        "com.macromates.textmate",
        "com.obsidian.md",
        "com.typora.typora",
        "com.ulyssesapp.mac",
        "com.zettlr.app",
        "org.markedit.markedit"
    ]
}

public struct ApplicationModeProfile: Codable, Equatable, Identifiable, Sendable {
    public let bundleIdentifier: String
    public var displayName: String
    public var mode: DictationMode

    public var id: String { bundleIdentifier }

    public init(bundleIdentifier: String, displayName: String, mode: DictationMode) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.mode = mode
    }
}

public enum ModeResolutionSource: Equatable, Sendable {
    case application(String)
    case group(ApplicationGroup)
    case defaultMode
}

public struct ModeResolution: Equatable, Sendable {
    public let mode: DictationMode
    public let source: ModeResolutionSource

    public init(mode: DictationMode, source: ModeResolutionSource) {
        self.mode = mode
        self.source = source
    }
}

public struct ApplicationModeConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var groupModes: [ApplicationGroup: DictationMode]
    public var applications: [ApplicationModeProfile]

    public init(
        enabled: Bool = true,
        groupModes: [ApplicationGroup: DictationMode] = [.terminal: .agent],
        applications: [ApplicationModeProfile] = []
    ) {
        self.enabled = enabled
        self.groupModes = groupModes
        self.applications = applications
    }

    public func resolve(
        bundleIdentifier: String?,
        defaultMode: DictationMode
    ) -> ModeResolution {
        guard enabled, let bundleIdentifier else {
            return ModeResolution(mode: defaultMode, source: .defaultMode)
        }

        if let profile = applications.first(where: {
            $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }) {
            return ModeResolution(
                mode: profile.mode,
                source: .application(profile.displayName)
            )
        }

        if let group = ApplicationGroup.classify(bundleIdentifier: bundleIdentifier),
           let mode = groupModes[group] {
            return ModeResolution(mode: mode, source: .group(group))
        }

        return ModeResolution(mode: defaultMode, source: .defaultMode)
    }
}
