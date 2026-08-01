import Foundation

public enum TextInsertionSegment: Equatable, Sendable {
    case text(String)
    case lineBreak
}

public enum TextInsertionPlan {
    public static func segments(
        for text: String,
        destination: DestinationApplicationKind
    ) -> [TextInsertionSegment] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if destination == .terminal {
            let flattened = normalized
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return flattened.isEmpty ? [] : [.text(flattened)]
        }

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var segments: [TextInsertionSegment] = []
        for (index, line) in lines.enumerated() {
            if !line.isEmpty { segments.append(.text(String(line))) }
            if index < lines.index(before: lines.endIndex) { segments.append(.lineBreak) }
        }
        return segments
    }
}
