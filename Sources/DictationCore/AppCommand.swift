import Foundation

public enum AppCommand: Equatable, Sendable {
    case setMode(DictationMode)

    public init?(url: URL) {
        guard url.scheme == "ian-dictation",
              url.host == "mode",
              let rawMode = url.pathComponents.dropFirst().first,
              let mode = DictationMode(rawValue: rawMode) else {
            return nil
        }
        self = .setMode(mode)
    }
}
