import Foundation

public enum FinalTranscriptFormatter {
    public static func punctuateRawProse(
        _ transcript: String,
        capitalizesInitial: Bool = true
    ) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let capitalized = capitalizesInitial ? capitalizeInitialWord(in: trimmed) : trimmed
        guard let finalCharacter = capitalized.last,
              finalCharacter.isLetter || finalCharacter.isNumber else {
            return capitalized
        }

        let finalToken = capitalized.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? ""
        let technicalCharacters = CharacterSet(charactersIn: "/\\@._-:=+<>[]{}()$~`")
        guard finalToken.rangeOfCharacter(from: technicalCharacters) == nil else {
            return capitalized
        }

        return capitalized + "."
    }

    private static func capitalizeInitialWord(in transcript: String) -> String {
        guard let tokenEnd = transcript.firstIndex(where: \.isWhitespace) else {
            return capitalizeTokenIfProse(transcript, in: transcript)
        }
        let token = String(transcript[..<tokenEnd])
        return capitalizeTokenIfProse(token, in: transcript)
    }

    private static func capitalizeTokenIfProse(_ token: String, in transcript: String) -> String {
        let technicalCharacters = CharacterSet(charactersIn: "/\\@._:=+<>[]{}$~`")
        guard token.rangeOfCharacter(from: technicalCharacters) == nil,
              let index = transcript.firstIndex(where: \.isLetter),
              transcript[index].isLowercase else {
            return transcript
        }
        var result = transcript
        result.replaceSubrange(index...index, with: String(transcript[index]).uppercased())
        return result
    }
}
