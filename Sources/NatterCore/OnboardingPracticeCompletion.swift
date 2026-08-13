public enum OnboardingPracticeCompletion {
    public static func hasNewWord(
        in text: String,
        after baselineWordCount: Int
    ) -> Bool {
        text.split(whereSeparator: \.isWhitespace).count > baselineWordCount
    }
}
