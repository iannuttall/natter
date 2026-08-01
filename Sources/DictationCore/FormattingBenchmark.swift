import Foundation

public struct FormattingFixture: Codable, Sendable {
    public let id: String
    public let category: String
    public let context: SpokenFormattingContext
    public let spoken: String
    public let deterministicExpected: String
    public let protected: [String]
    public let forbidden: [String]
    public let smartInstructions: String?
    public let smartExpected: String?
    public let smartRequired: [String]?
    public let smartForbidden: [String]?
}

public struct FormattingFixtureSet: Codable, Sendable {
    public let version: Int
    public let fixtures: [FormattingFixture]
}

public struct FormattingFixtureResult: Codable, Sendable {
    public let id: String
    public let category: String
    public let passed: Bool
    public let exact: Bool
    public let protectedPassed: Int
    public let protectedTotal: Int
    public let forbiddenPassed: Int
    public let forbiddenTotal: Int
    public let expected: String
    public let output: String
}

public struct FormattingSummary: Codable, Sendable {
    public let fixtures: Int
    public let passed: Int
    public let exactPassRate: Double
    public let protectedPassRate: Double
    public let forbiddenPassRate: Double
    public let results: [FormattingFixtureResult]
}

public enum FormattingBenchmark {
    public static func evaluate(_ fixture: FormattingFixture) -> FormattingFixtureResult {
        let output = SpokenTechnicalTextNormalizer.normalize(
            fixture.spoken,
            context: fixture.context
        )
        let protectedPassed = fixture.protected.filter { output.contains($0) }.count
        let forbiddenPassed = fixture.forbidden.filter { !output.contains($0) }.count
        let exact = output == fixture.deterministicExpected
        return FormattingFixtureResult(
            id: fixture.id,
            category: fixture.category,
            passed: exact
                && protectedPassed == fixture.protected.count
                && forbiddenPassed == fixture.forbidden.count,
            exact: exact,
            protectedPassed: protectedPassed,
            protectedTotal: fixture.protected.count,
            forbiddenPassed: forbiddenPassed,
            forbiddenTotal: fixture.forbidden.count,
            expected: fixture.deterministicExpected,
            output: output
        )
    }

    public static func summarize(_ results: [FormattingFixtureResult]) -> FormattingSummary {
        let protectedPassed = results.reduce(0) { $0 + $1.protectedPassed }
        let protectedTotal = results.reduce(0) { $0 + $1.protectedTotal }
        let forbiddenPassed = results.reduce(0) { $0 + $1.forbiddenPassed }
        let forbiddenTotal = results.reduce(0) { $0 + $1.forbiddenTotal }
        return FormattingSummary(
            fixtures: results.count,
            passed: results.filter(\.passed).count,
            exactPassRate: rate(results.filter(\.exact).count, results.count),
            protectedPassRate: rate(protectedPassed, protectedTotal),
            forbiddenPassRate: rate(forbiddenPassed, forbiddenTotal),
            results: results
        )
    }

    public static func smartWritingFixture(from fixture: FormattingFixture) -> WritingFixture? {
        guard let instructions = fixture.smartInstructions,
              let expected = fixture.smartExpected else {
            return nil
        }
        return WritingFixture(
            id: fixture.id,
            mode: "Smart formatting",
            instructions: instructions,
            transcript: fixture.deterministicExpected,
            expected: expected,
            required: fixture.smartRequired ?? fixture.protected,
            forbidden: fixture.smartForbidden ?? fixture.forbidden
        )
    }

    private static func rate(_ passed: Int, _ total: Int) -> Double {
        total == 0 ? 1 : Double(passed) / Double(total)
    }
}
