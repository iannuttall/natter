import Foundation

public struct VoiceSubmitResult: Equatable, Sendable {
    public let transcript: String
    public let shouldSubmit: Bool

    public init(transcript: String, shouldSubmit: Bool) {
        self.transcript = transcript
        self.shouldSubmit = shouldSubmit
    }
}

public enum VoiceSubmitCommand {
    private static let commands: Set<String> = ["enter", "send"]
    private static let danglingSeparators = CharacterSet(charactersIn: ",;:")

    public static func consume(from transcript: String) -> VoiceSubmitResult {
        var commandEnd = transcript.endIndex
        while commandEnd > transcript.startIndex {
            let previous = transcript.index(before: commandEnd)
            let character = transcript[previous]
            guard character.isWhitespace || character.unicodeScalars.allSatisfy(
                CharacterSet.punctuationCharacters.contains
            ) else { break }
            commandEnd = previous
        }

        var commandStart = commandEnd
        while commandStart > transcript.startIndex {
            let previous = transcript.index(before: commandStart)
            guard transcript[previous].isLetter else { break }
            commandStart = previous
        }

        let command = transcript[commandStart..<commandEnd].lowercased()
        guard commands.contains(command) else {
            return VoiceSubmitResult(transcript: transcript, shouldSubmit: false)
        }

        var contentEnd = commandStart
        while contentEnd > transcript.startIndex,
              transcript[transcript.index(before: contentEnd)].isWhitespace {
            contentEnd = transcript.index(before: contentEnd)
        }
        while contentEnd > transcript.startIndex {
            let previous = transcript.index(before: contentEnd)
            let scalars = transcript[previous].unicodeScalars
            guard scalars.allSatisfy(danglingSeparators.contains) else { break }
            contentEnd = previous
        }

        guard contentEnd > transcript.startIndex else {
            return VoiceSubmitResult(transcript: transcript, shouldSubmit: false)
        }

        return VoiceSubmitResult(
            transcript: String(transcript[..<contentEnd]),
            shouldSubmit: true
        )
    }
}
