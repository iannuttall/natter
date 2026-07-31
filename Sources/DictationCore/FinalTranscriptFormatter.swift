import Foundation

public enum FinalTranscriptFormatter {
    public static func punctuateRawProse(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let finalCharacter = trimmed.last,
              finalCharacter.isLetter || finalCharacter.isNumber else {
            return trimmed
        }

        let finalToken = trimmed.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        let technicalCharacters = CharacterSet(charactersIn: "/\\@._-:=+<>[]{}()$~`")
        guard finalToken.rangeOfCharacter(from: technicalCharacters) == nil else {
            return trimmed
        }

        return trimmed + "."
    }
}
