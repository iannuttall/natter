import Foundation

public enum TranscriptEditApplicationError: LocalizedError, Equatable {
    case emptySource
    case unchangedEdit(String)
    case sourceNotUnique(String, matches: Int)
    case unsafeAllOccurrencesSource(String)
    case altersProtectedTerminology(String)
    case overlappingEdits
    case changeBudgetExceeded(changed: Int, allowed: Int)

    public var errorDescription: String? {
        switch self {
        case .emptySource:
            "The writing model proposed an edit with no source text."
        case .unchangedEdit(let source):
            "The writing model proposed an unchanged edit for “\(source)”."
        case .sourceNotUnique(let source, let matches):
            "The writing model edit source “\(source)” matched \(matches) times."
        case .unsafeAllOccurrencesSource(let source):
            "The writing model bulk-edit source “\(source)” did not include enough context."
        case .altersProtectedTerminology(let term):
            "The writing model tried to alter the protected spelling “\(term)”."
        case .overlappingEdits:
            "The writing model proposed overlapping edits."
        case .changeBudgetExceeded(let changed, let allowed):
            "The writing model tried to change \(changed) characters; the safe limit is \(allowed)."
        }
    }
}

public enum TranscriptEditApplier {
    public static func applyRecovering(
        _ plan: TranscriptEditPlan,
        to transcript: String,
        protectedTerms: [String] = []
    ) -> TranscriptEditRecoveryResult {
        var accepted: [TranscriptEdit] = []
        var rejectedCount = 0
        for edit in plan.edits where edit.source != edit.replacement {
            let candidate = TranscriptEditPlan(edits: accepted + [edit])
            do {
                _ = try apply(
                    candidate,
                    to: transcript,
                    protectedTerms: protectedTerms
                )
                accepted.append(edit)
            } catch {
                rejectedCount += 1
            }
        }

        let output =
            (try? apply(
                TranscriptEditPlan(edits: accepted),
                to: transcript,
                protectedTerms: protectedTerms
            )) ?? transcript
        return TranscriptEditRecoveryResult(
            output: output,
            acceptedPlan: TranscriptEditPlan(edits: accepted),
            rejectedEdits: rejectedCount
        )
    }

    public static func apply(
        _ plan: TranscriptEditPlan,
        to transcript: String,
        protectedTerms: [String] = []
    ) throws -> String {
        var resolved: [(range: Range<String.Index>, edit: TranscriptEdit)] = []
        for edit in plan.edits {
            guard !edit.source.isEmpty else {
                throw TranscriptEditApplicationError.emptySource
            }
            guard edit.source != edit.replacement else { continue }
            var matches = ranges(of: edit.source, in: transcript)
            if matches.isEmpty,
                edit.source.split(whereSeparator: \.isWhitespace).count >= 5
            {
                matches = ranges(
                    of: edit.source,
                    in: transcript,
                    options: .caseInsensitive
                )
            }
            let editRanges: [Range<String.Index>]
            if edit.allOccurrences == true {
                let sourceWords = edit.source.split(whereSeparator: \.isWhitespace).count
                let hasSafeBulkContext =
                    sourceWords >= 3
                    || ((sourceWords == 1 || sourceWords == 2)
                        && bulkContextsAreEquivalent(matches, in: transcript))
                guard matches.count == 1 || hasSafeBulkContext else {
                    throw TranscriptEditApplicationError.unsafeAllOccurrencesSource(
                        edit.source
                    )
                }
                guard edit.occurrence == nil, !matches.isEmpty else {
                    throw TranscriptEditApplicationError.sourceNotUnique(
                        edit.source,
                        matches: matches.count
                    )
                }
                editRanges = matches
            } else if let occurrence = edit.occurrence {
                guard occurrence > 0, occurrence <= matches.count else {
                    throw TranscriptEditApplicationError.sourceNotUnique(
                        edit.source,
                        matches: matches.count
                    )
                }
                editRanges = [matches[occurrence - 1]]
            } else if matches.count == 1, let onlyMatch = matches.first {
                editRanges = [onlyMatch]
            } else {
                throw TranscriptEditApplicationError.sourceNotUnique(
                    edit.source,
                    matches: matches.count
                )
            }
            for range in editRanges {
                let actualSource = String(transcript[range])
                if let protectedTerm = protectedTerms.first(where: { term in
                    let sourceCount = ranges(of: term, in: actualSource).count
                    return sourceCount > 0
                        && ranges(of: term, in: edit.replacement).count != sourceCount
                }) {
                    throw TranscriptEditApplicationError.altersProtectedTerminology(
                        protectedTerm
                    )
                }
                let overlapping = resolved.indices.filter {
                    resolved[$0].range.overlaps(range)
                }
                if !overlapping.isEmpty {
                    let candidateContainsExisting = overlapping.allSatisfy { index in
                        rangeContains(range, resolved[index].range)
                            && edit.replacement.contains(resolved[index].edit.replacement)
                    }
                    if candidateContainsExisting {
                        for index in overlapping.reversed() {
                            resolved.remove(at: index)
                        }
                    } else if overlapping.count == 1 {
                        let existing = resolved[overlapping[0]]
                        if rangeContains(existing.range, range),
                            existing.edit.replacement.contains(edit.replacement)
                        {
                            continue
                        }
                        throw TranscriptEditApplicationError.overlappingEdits
                    } else {
                        throw TranscriptEditApplicationError.overlappingEdits
                    }
                }
                resolved.append((range, edit))
            }
        }

        let changedCharacters = resolved.reduce(into: 0) { total, resolvedEdit in
            total += changedCharacterCount(
                from: String(transcript[resolvedEdit.range]),
                to: resolvedEdit.edit.replacement
            )
        }
        let allowedChanges = max(24, transcript.count / 3)
        guard changedCharacters <= allowedChanges else {
            throw TranscriptEditApplicationError.changeBudgetExceeded(
                changed: changedCharacters,
                allowed: allowedChanges
            )
        }

        var output = transcript
        for resolvedEdit in resolved.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            output.replaceSubrange(resolvedEdit.range, with: resolvedEdit.edit.replacement)
        }
        return output
    }

    private static func rangeContains(
        _ outer: Range<String.Index>,
        _ inner: Range<String.Index>
    ) -> Bool {
        outer.lowerBound <= inner.lowerBound && outer.upperBound >= inner.upperBound
    }

    private static func bulkContextsAreEquivalent(
        _ matches: [Range<String.Index>],
        in transcript: String
    ) -> Bool {
        guard let first = matches.first, matches.count > 1 else { return true }
        let expected = bulkContext(around: first, in: transcript)
        return matches.dropFirst().allSatisfy {
            bulkContext(around: $0, in: transcript) == expected
        }
    }

    private static func bulkContext(
        around range: Range<String.Index>,
        in transcript: String
    ) -> [String] {
        let before = transcript[..<range.lowerBound]
            .split(whereSeparator: \.isWhitespace)
            .suffix(5)
        return before.map { token in
            let lowered = token.lowercased()
            return lowered.contains(where: \.isNumber) ? "#" : lowered
        }
    }

    private static func ranges(
        of source: String,
        in transcript: String,
        options: String.CompareOptions = .literal
    ) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var searchStart = transcript.startIndex
        while searchStart < transcript.endIndex,
            let range = transcript.range(
                of: source,
                options: options,
                range: searchStart..<transcript.endIndex
            )
        {
            result.append(range)
            searchStart = range.upperBound
        }
        return result
    }

    private static func changedCharacterCount(from source: String, to replacement: String) -> Int {
        let sourceCharacters = Array(source)
        let replacementCharacters = Array(replacement)
        guard !sourceCharacters.isEmpty else { return replacementCharacters.count }
        guard !replacementCharacters.isEmpty else { return sourceCharacters.count }

        var previous = Array(0...replacementCharacters.count)
        for (sourceIndex, sourceCharacter) in sourceCharacters.enumerated() {
            var current =
                [sourceIndex + 1]
                + Array(repeating: 0, count: replacementCharacters.count)
            for (replacementIndex, replacementCharacter) in replacementCharacters.enumerated() {
                current[replacementIndex + 1] = min(
                    current[replacementIndex] + 1,
                    previous[replacementIndex + 1] + 1,
                    previous[replacementIndex]
                        + (sourceCharacter == replacementCharacter ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[replacementCharacters.count]
    }
}
