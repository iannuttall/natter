import Foundation

public enum AgentTranscriptChunker {
    public static let productionMaximumWords = 400
    public static let minimumRetryWords = 64

    public static func chunks(
        _ transcript: String,
        maximumWords: Int = productionMaximumWords
    ) -> [String] {
        guard maximumWords > 0, !transcript.isEmpty else { return [transcript] }
        let words = wordRanges(in: transcript)
        guard words.count > maximumWords else { return [transcript] }

        var result: [String] = []
        var chunkStart = transcript.startIndex
        var firstWord = 0
        while firstWord < words.count {
            let proposedEnd = min(firstWord + maximumWords, words.count)
            guard proposedEnd < words.count else {
                result.append(String(transcript[chunkStart..<transcript.endIndex]))
                break
            }

            let earliestPreferredEnd = firstWord + maximumWords / 2
            var lastWord = proposedEnd - 1
            if earliestPreferredEnd < proposedEnd {
                for candidate in stride(
                    from: proposedEnd - 1,
                    through: earliestPreferredEnd,
                    by: -1
                ) where endsSentence(transcript[words[candidate]]) {
                    lastWord = candidate
                    break
                }
            }

            let nextWord = lastWord + 1
            let chunkEnd = words[nextWord].lowerBound
            result.append(String(transcript[chunkStart..<chunkEnd]))
            chunkStart = chunkEnd
            firstWord = nextWord
        }
        return result
    }

    public static func wordCount(_ transcript: String) -> Int {
        transcript.split(whereSeparator: \.isWhitespace).count
    }

    private static func wordRanges(in transcript: String) -> [Range<String.Index>] {
        guard let expression = try? NSRegularExpression(pattern: #"\S+"#) else { return [] }
        return expression.matches(
            in: transcript,
            range: NSRange(transcript.startIndex..., in: transcript)
        ).compactMap { Range($0.range, in: transcript) }
    }

    private static func endsSentence(_ word: Substring) -> Bool {
        word.last.map { ".!?".contains($0) } ?? false
    }
}
