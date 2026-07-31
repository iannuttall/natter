import Foundation

public enum DestinationApplicationKind: Equatable, Sendable {
    case standard
    case terminal

    public static func classify(bundleIdentifier: String?) -> Self {
        guard let identifier = bundleIdentifier?.lowercased() else { return .standard }
        return terminalBundleIdentifiers.contains(identifier) ? .terminal : .standard
    }

    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.terminal",
        "com.electron.tabby",
        "com.github.wez.wezterm",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.raphaelamorim.rio",
        "dev.warp.warp-stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "org.contour-terminal.contour"
    ]
}
