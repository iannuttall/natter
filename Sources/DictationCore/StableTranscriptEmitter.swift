import Foundation

public enum TranscriptEmission: Equatable, Sendable {
    case none
    case text(String)
    case conflict
}

public struct StableTranscriptEmitter: Sendable {
    public private(set) var delivered = ""
    private var previous = ""

    public init() {}

    public mutating func observe(_ transcript: String) -> TranscriptEmission {
        defer { previous = transcript }

        guard transcript.hasPrefix(delivered) else { return .conflict }
        guard !previous.isEmpty else { return .none }

        let common = String(previous.commonPrefix(with: transcript))
        let stable = stablePrefix(of: common, in: transcript)
        guard stable.count > delivered.count else { return .none }
        guard stable.hasPrefix(delivered) else { return .conflict }

        let addition = String(stable.dropFirst(delivered.count))
        delivered = stable
        return addition.isEmpty ? .none : .text(addition)
    }

    public mutating func finish(_ transcript: String) -> TranscriptEmission {
        guard transcript.hasPrefix(delivered) else { return .conflict }
        let addition = String(transcript.dropFirst(delivered.count))
        delivered = transcript
        previous = transcript
        return addition.isEmpty ? .none : .text(addition)
    }

    public mutating func reset() {
        delivered = ""
        previous = ""
    }

    private func stablePrefix(of common: String, in current: String) -> String {
        guard !common.isEmpty else { return "" }

        let commonEnd = current.index(current.startIndex, offsetBy: common.count)
        if commonEnd < current.endIndex, current[commonEnd].isWhitespace {
            return common
        }

        guard let finalWhitespace = common.lastIndex(where: \.isWhitespace) else {
            return ""
        }
        return String(common[...finalWhitespace])
    }
}
