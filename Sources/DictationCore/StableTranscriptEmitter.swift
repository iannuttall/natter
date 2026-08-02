import Foundation

public enum TranscriptEmission: Equatable, Sendable {
    case none
    case text(String)
    case conflict
}

public struct StableTranscriptEmitter: Sendable {
    public private(set) var delivered = ""

    public init() {}

    public mutating func observe(_ transcript: String) -> TranscriptEmission {
        guard transcript.hasPrefix(delivered) else { return .conflict }
        let addition = String(transcript.dropFirst(delivered.count))
        delivered = transcript
        return addition.isEmpty ? .none : .text(addition)
    }

    public mutating func finish(_ transcript: String) -> TranscriptEmission {
        guard transcript.hasPrefix(delivered) else { return .conflict }
        let addition = String(transcript.dropFirst(delivered.count))
        delivered = transcript
        return addition.isEmpty ? .none : .text(addition)
    }

    public func remainingText(in transcript: String) -> String? {
        guard transcript.hasPrefix(delivered) else { return nil }
        return String(transcript.dropFirst(delivered.count))
    }

    public mutating func reset() {
        delivered = ""
    }
}
