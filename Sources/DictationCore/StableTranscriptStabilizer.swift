import Foundation

public enum TranscriptStabilization: Equatable, Sendable {
    case prefix(String)
    case conflict
}

public struct StableTranscriptStabilizer: Sendable {
    private let trailingTokenCount: Int
    private var previousHypothesis = ""
    public private(set) var stablePrefix = ""

    public init(trailingTokenCount: Int) {
        self.trailingTokenCount = max(0, trailingTokenCount)
    }

    public mutating func observe(_ hypothesis: String) -> TranscriptStabilization {
        defer { previousHypothesis = hypothesis }
        guard !previousHypothesis.isEmpty else { return .prefix(stablePrefix) }
        guard hypothesis.hasPrefix(stablePrefix) else { return .conflict }

        let shared = commonPrefix(previousHypothesis, hypothesis)
        let candidate = droppingTrailingTokens(from: shared, count: trailingTokenCount)
        guard candidate.hasPrefix(stablePrefix) else { return .prefix(stablePrefix) }

        stablePrefix = candidate
        return .prefix(candidate)
    }

    private func commonPrefix(_ lhs: String, _ rhs: String) -> String {
        let characters = zip(lhs, rhs).prefix { $0 == $1 }.map(\.0)
        return String(characters)
    }

    private func droppingTrailingTokens(from text: String, count: Int) -> String {
        guard count > 0,
              let regex = try? NSRegularExpression(pattern: #"\S+"#) else {
            return text
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count > count,
              let cutoff = Range(matches[matches.count - count].range, in: text)?.lowerBound else {
            return ""
        }
        return String(text[..<cutoff])
    }
}
