import Foundation

public enum TextInsertionSegment: Equatable, Sendable {
    case text(String)
    case lineBreak
}

public enum TextInsertionPlan {
    public static func chunks(
        for text: String,
        maximumCharacterCount: Int
    ) -> [String] {
        guard !text.isEmpty, maximumCharacterCount > 0 else { return [] }
        var chunks: [String] = []
        var current = ""
        var currentCount = 0

        for character in text {
            current.append(character)
            currentCount += 1
            if currentCount == maximumCharacterCount {
                chunks.append(current)
                current = ""
                currentCount = 0
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    public static func segments(
        for text: String,
        destination: DestinationApplicationKind
    ) -> [TextInsertionSegment] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if destination == .terminal {
            let flattened = normalized.replacingOccurrences(
                of: #"[ \t]*\n+[ \t]*"#,
                with: " ",
                options: .regularExpression
            )
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
