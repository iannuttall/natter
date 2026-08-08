import Foundation

public struct TranscriptEdit: Codable, Equatable, Sendable {
    public let source: String
    public let replacement: String
    public let occurrence: Int?
    public let allOccurrences: Bool?

    public init(
        source: String,
        replacement: String,
        occurrence: Int? = nil,
        allOccurrences: Bool = false
    ) {
        self.source = source
        self.replacement = replacement
        self.occurrence = occurrence
        self.allOccurrences = allOccurrences
    }
}

public struct TranscriptEditPlan: Codable, Equatable, Sendable {
    public let edits: [TranscriptEdit]

    public init(edits: [TranscriptEdit]) {
        self.edits = edits
    }
}

public struct TranscriptEditRecoveryResult: Equatable, Sendable {
    public let output: String
    public let acceptedPlan: TranscriptEditPlan
    public let rejectedEdits: Int

    public var acceptedEdits: Int { acceptedPlan.edits.count }

    public init(
        output: String,
        acceptedPlan: TranscriptEditPlan,
        rejectedEdits: Int
    ) {
        self.output = output
        self.acceptedPlan = acceptedPlan
        self.rejectedEdits = rejectedEdits
    }
}

public enum AgentSelfEditPolicy {
    private static let cuePattern =
        #"(?i)\b(?:delete|ignore|scratch)\s+(?:that|this|it|that\s+part)\b|\bchange\s+(?:that|this|it)\s+to\b|\bi\s+mean\b|\bthere\s+we\s+go[,]?\s+that(?:'|’)s\s+better\b"#

    public static func containsCorrectionCue(_ transcript: String) -> Bool {
        transcript.range(of: cuePattern, options: .regularExpression) != nil
    }

    public static func safePlan(from plan: TranscriptEditPlan) -> TranscriptEditPlan {
        TranscriptEditPlan(edits: plan.edits.filter(isSafe))
    }

    public static func safeOutput(
        input: String,
        proposedOutput: String
    ) -> String? {
        let inputWords = WritingBenchmark.normalizedWords(input)
        let outputWords = WritingBenchmark.normalizedWords(proposedOutput)
        if outputWords == inputWords { return input }
        guard !outputWords.isEmpty,
            let retainedIndexes = backwardSubsequenceIndexes(
                outputWords,
                in: inputWords
            )
        else {
            return nil
        }

        let retained = Set(retainedIndexes)
        guard cueDirectionIsValid(inputWords: inputWords, retained: retained) else {
            return nil
        }
        var removedRanges: [Range<Int>] = []
        var start: Int?
        for index in inputWords.indices {
            if retained.contains(index) {
                if let rangeStart = start {
                    removedRanges.append(rangeStart..<index)
                    start = nil
                }
            } else if start == nil {
                start = index
            }
        }
        if let start { removedRanges.append(start..<inputWords.count) }
        guard !removedRanges.isEmpty else { return nil }

        let removedTexts = removedRanges.map {
            inputWords[$0].joined(separator: " ")
        }
        let cueRanges = removedTexts.indices.filter {
            containsCorrectionCue(removedTexts[$0])
        }
        guard !cueRanges.isEmpty else { return nil }
        let hasAcknowledgement =
            input.range(
                of: #"(?i)\bthere\s+we\s+go[,]?\s+that(?:'|’)s\s+better\b"#,
                options: .regularExpression
            ) != nil
        guard
            removedTexts.indices.allSatisfy({ index in
                containsCorrectionCue(removedTexts[index]) || hasAcknowledgement
            })
        else {
            return nil
        }
        guard
            removedTexts.allSatisfy({
                WritingBenchmark.normalizedWords($0).count >= 3
            })
        else {
            return nil
        }
        let removedWordCount = removedRanges.reduce(0) { $0 + $1.count }
        guard removedWordCount > cueRanges.count * 2 else { return nil }
        return proposedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cueDirectionIsValid(
        inputWords: [String],
        retained: Set<Int>
    ) -> Bool {
        let standardCues = [
            ["ignore", "that", "part"],
            ["there", "we", "go", "that's", "better"],
            ["change", "that", "to"],
            ["change", "this", "to"],
            ["change", "it", "to"],
            ["delete", "that"], ["delete", "this"], ["delete", "it"],
            ["ignore", "that"], ["ignore", "this"], ["ignore", "it"],
            ["scratch", "that"], ["scratch", "this"], ["scratch", "it"],
            ["i", "mean"],
        ]
        var cueRanges: [Range<Int>] = []
        var index = 0
        while index < inputWords.count {
            if let cue = standardCues.first(where: { candidate in
                index + candidate.count <= inputWords.count
                    && Array(inputWords[index..<(index + candidate.count)]) == candidate
            }) {
                cueRanges.append(index..<(index + cue.count))
                index += cue.count
            } else {
                index += 1
            }
        }
        guard !cueRanges.isEmpty else { return false }
        return cueRanges.allSatisfy { cueRange in
            let cueWasRemoved = cueRange.allSatisfy { !retained.contains($0) }
            let removedBefore = (0..<cueRange.lowerBound).contains {
                !retained.contains($0)
            }
            if inputWords[cueRange].joined(separator: " ")
                == "there we go that's better"
            {
                return cueWasRemoved && removedBefore
            }
            let retainedAfter = (cueRange.upperBound..<inputWords.count).contains {
                retained.contains($0)
            }
            let wordsBeforeCue = Set(inputWords[..<cueRange.lowerBound])
            let distinctiveAfter = (cueRange.upperBound..<inputWords.count).filter {
                !wordsBeforeCue.contains(inputWords[$0])
            }
            let retainedDistinctiveAfter =
                distinctiveAfter.isEmpty
                || distinctiveAfter.contains { retained.contains($0) }
            return cueWasRemoved
                && removedBefore
                && retainedAfter
                && retainedDistinctiveAfter
        }
    }

    private static func backwardSubsequenceIndexes(
        _ subsequence: [String],
        in words: [String]
    ) -> [Int]? {
        var result = Array(repeating: 0, count: subsequence.count)
        var searchEnd = words.count
        for outputIndex in subsequence.indices.reversed() {
            guard searchEnd > 0,
                let match = words[..<searchEnd].lastIndex(of: subsequence[outputIndex])
            else {
                return nil
            }
            result[outputIndex] = match
            searchEnd = match
        }
        return result
    }

    public static func removingResidualAcknowledgementCues(from transcript: String) -> String {
        let pattern = #"(?i)(?:[,;:—-]\s*)?\bthere\s+we\s+go[,]?\s+that(?:'|’)s\s+better\b[,.!?]?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return transcript
        }
        let range = NSRange(transcript.startIndex..., in: transcript)
        let cleaned = expression.stringByReplacingMatches(
            in: transcript,
            range: range,
            withTemplate: ""
        )
        return
            cleaned
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSafe(_ edit: TranscriptEdit) -> Bool {
        guard edit.source != edit.replacement,
            edit.occurrence == nil,
            edit.allOccurrences != true,
            containsCorrectionCue(edit.source),
            AgentTranscriptChunker.wordCount(edit.source) <= 60
        else {
            return false
        }
        let sourceWords = WritingBenchmark.normalizedWords(edit.source)
        let replacementWords = WritingBenchmark.normalizedWords(edit.replacement)
        guard replacementUsesCorrectedSide(edit) else { return false }
        var sourceIndex = sourceWords.startIndex
        for replacementWord in replacementWords {
            guard let match = sourceWords[sourceIndex...].firstIndex(of: replacementWord) else {
                return false
            }
            sourceIndex = sourceWords.index(after: match)
        }
        return true
    }

    private static func replacementUsesCorrectedSide(_ edit: TranscriptEdit) -> Bool {
        let replacementWords = WritingBenchmark.normalizedWords(edit.replacement)
        let acknowledgementPattern = #"(?i)\bthere\s+we\s+go[,]?\s+that(?:'|’)s\s+better\b"#
        if edit.source.range(of: acknowledgementPattern, options: .regularExpression) != nil {
            return true
        }
        guard let cueRange = edit.source.range(of: cuePattern, options: .regularExpression) else {
            return false
        }
        if replacementWords.isEmpty {
            return WritingBenchmark.normalizedWords(
                String(edit.source[..<cueRange.lowerBound])
            ).count >= 2
        }
        let correctedWords = WritingBenchmark.normalizedWords(
            String(edit.source[cueRange.upperBound...])
        )
        guard !correctedWords.isEmpty else { return false }
        var correctedIndex = correctedWords.startIndex
        for replacementWord in replacementWords {
            guard let match = correctedWords[correctedIndex...].firstIndex(of: replacementWord)
            else {
                return false
            }
            correctedIndex = correctedWords.index(after: match)
        }
        return true
    }
}
