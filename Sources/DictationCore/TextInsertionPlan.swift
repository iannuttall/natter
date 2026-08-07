import Foundation

public enum TextInsertionPlan {
    public struct SelectionReplacement: Equatable, Sendable {
        public let text: String
        public let cursorUTF16Location: Int

        public init(text: String, cursorUTF16Location: Int) {
            self.text = text
            self.cursorUTF16Location = cursorUTF16Location
        }
    }

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

    public static func insertionText(
        for text: String,
        destination: DestinationApplicationKind
    ) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // A shell prompt runs every newline it receives, so terminals get one
        // flattened line. Standard apps receive newlines as pasted characters,
        // which never fires a composer's Return-to-send handler.
        guard destination == .terminal else { return normalized }
        return normalized.replacingOccurrences(
            of: #"[ \t]*\n+[ \t]*"#,
            with: " ",
            options: .regularExpression
        )
    }

    public static func replacingSelection(
        in value: String,
        utf16Location: Int,
        utf16Length: Int,
        with replacement: String
    ) -> SelectionReplacement? {
        let range = NSRange(location: utf16Location, length: utf16Length)
        let value = value as NSString
        guard range.location >= 0, range.length >= 0,
              NSMaxRange(range) <= value.length else {
            return nil
        }
        return SelectionReplacement(
            text: value.replacingCharacters(in: range, with: replacement),
            cursorUTF16Location: range.location + replacement.utf16.count
        )
    }
}
