import Testing

@testable import NatterCore

@Test func dictationModesCycleInDisplayedOrder() {
    #expect(DictationMode.raw.next == .agent)
    #expect(DictationMode.agent.next == .clean)
    #expect(DictationMode.clean.next == .email)
    #expect(DictationMode.email.next == .article)
    #expect(DictationMode.article.next == .raw)
}

@Test func appModeProfilesPreferExactAppThenGroupThenDefault() {
    let configuration = ApplicationModeConfiguration(
        groupModes: [.terminal: .agent, .mail: .email],
        applications: [
            ApplicationModeProfile(
                bundleIdentifier: "com.mitchellh.ghostty",
                displayName: "Ghostty",
                mode: .raw
            )
        ]
    )

    #expect(
        configuration.resolve(
            bundleIdentifier: "com.mitchellh.ghostty",
            defaultMode: .clean
        ) == ModeResolution(mode: .raw, source: .application("Ghostty")))
    #expect(
        configuration.resolve(
            bundleIdentifier: "com.apple.Terminal",
            defaultMode: .clean
        ) == ModeResolution(mode: .agent, source: .group(.terminal)))
    #expect(
        configuration.resolve(
            bundleIdentifier: "com.apple.mail",
            defaultMode: .raw
        ) == ModeResolution(mode: .email, source: .group(.mail)))
    #expect(
        configuration.resolve(
            bundleIdentifier: "com.apple.TextEdit",
            defaultMode: .clean
        ) == ModeResolution(mode: .clean, source: .defaultMode))
}

@Test func disabledAppModeProfilesAlwaysUseDefault() {
    let configuration = ApplicationModeConfiguration(
        enabled: false,
        groupModes: [.terminal: .agent]
    )

    #expect(
        configuration.resolve(
            bundleIdentifier: "com.apple.Terminal",
            defaultMode: .raw
        ) == ModeResolution(mode: .raw, source: .defaultMode))
}
