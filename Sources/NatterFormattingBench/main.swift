import NatterCore
import Foundation

@main
private enum NatterFormattingBench {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2, arguments[0] == "--fixtures" else {
            FileHandle.standardError.write(Data(
                "Usage: natter-formatting-bench --fixtures <path>\n".utf8
            ))
            exit(2)
        }

        let url = URL(fileURLWithPath: arguments[1])
        let fixtureSet = try JSONDecoder().decode(
            FormattingFixtureSet.self,
            from: Data(contentsOf: url)
        )
        let summary = FormattingBenchmark.summarize(
            fixtureSet.fixtures.map(FormattingBenchmark.evaluate)
        )

        for result in summary.results where !result.passed {
            print("FAIL \(result.id)")
            print("  expected: \(result.expected)")
            print("  actual:   \(result.output)")
        }
        print("Formatting: \(summary.passed)/\(summary.fixtures)")
        print(String(format: "Exact: %.1f%%", summary.exactPassRate * 100))
        print(String(format: "Protected: %.1f%%", summary.protectedPassRate * 100))
        print(String(format: "Forbidden: %.1f%%", summary.forbiddenPassRate * 100))
        if summary.passed != summary.fixtures {
            exit(1)
        }
    }
}
