import Foundation
import Testing

@testable import NatterCore

@Test func onboardingStopsAtTheFirstIncompleteRequirement() {
    var snapshot = OnboardingSnapshot(
        welcomed: false,
        speechModelInstalled: false,
        microphoneGranted: false,
        accessibilityGranted: false,
        inputMonitoringGranted: false,
        practiceCompleted: false,
        writingChoiceCompleted: false
    )
    #expect(snapshot.currentStep == .welcome)

    snapshot = OnboardingSnapshot(
        welcomed: true,
        speechModelInstalled: false,
        microphoneGranted: true,
        accessibilityGranted: true,
        inputMonitoringGranted: true,
        practiceCompleted: true,
        writingChoiceCompleted: true
    )
    #expect(snapshot.currentStep == .speechModel)

    snapshot = OnboardingSnapshot(
        welcomed: true,
        speechModelInstalled: true,
        microphoneGranted: true,
        accessibilityGranted: false,
        inputMonitoringGranted: true,
        practiceCompleted: true,
        writingChoiceCompleted: true
    )
    #expect(snapshot.currentStep == .permissions)
}

@Test func writingModelChoiceIsOptionalButExplicit() {
    let pending = OnboardingSnapshot(
        welcomed: true,
        speechModelInstalled: true,
        microphoneGranted: true,
        accessibilityGranted: true,
        inputMonitoringGranted: true,
        practiceCompleted: true,
        writingChoiceCompleted: false
    )
    #expect(pending.currentStep == .writingModel)
    #expect(!pending.isReadyToComplete)

    let ready = OnboardingSnapshot(
        welcomed: true,
        speechModelInstalled: true,
        microphoneGranted: true,
        accessibilityGranted: true,
        inputMonitoringGranted: true,
        practiceCompleted: true,
        writingChoiceCompleted: true
    )
    #expect(ready.currentStep == .ready)
    #expect(ready.isReadyToComplete)
    #expect(ready.essentialSetupIsValid)
}

@Test func modesSeparateLiveAndGenerativeDelivery() {
    #expect(!DictationMode.raw.typesIncrementally)
    #expect(!DictationMode.agent.typesIncrementally)
    #expect(!DictationMode.clean.typesIncrementally)
    #expect(!DictationMode.clean.isGenerative)
    #expect(DictationMode.email.isGenerative)
    #expect(DictationMode.article.isGenerative)
}

@Test func customModeIdentifiersKeepLegacyStringEncoding() throws {
    let mode = try #require(DictationMode(rawValue: "client-notes"))
    let data = try JSONEncoder().encode(mode)

    #expect(String(decoding: data, as: UTF8.self) == "\"client-notes\"")
    #expect(try JSONDecoder().decode(DictationMode.self, from: data) == mode)
    #expect(DictationMode(rawValue: "Not Valid!") == nil)
}

@Test func modeConfigurationsRoundTripCustomProcessingAndInstructions() throws {
    let customID = try #require(DictationMode(rawValue: "client-update"))
    let configuration = ModeConfiguration(modes: [
        ModeDefinition(
            id: customID,
            name: "Client update",
            processing: .rewrite,
            instructions: "Use short headings.",
            removesFalseStarts: true
        )
    ])

    let data = try JSONEncoder().encode(configuration)
    #expect(try JSONDecoder().decode(ModeConfiguration.self, from: data) == configuration)
    #expect(DictationMode.agent.defaultProcessing == .fast)
    #expect(DictationMode.clean.defaultProcessing == .refine)
    #expect(DictationMode.article.defaultProcessing == .rewrite)
}

@Test func knownTerminalsUseTerminalDelivery() {
    for bundleIdentifier in [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "org.alacritty",
    ] {
        #expect(
            DestinationApplicationKind.classify(bundleIdentifier: bundleIdentifier) == .terminal)
    }

    #expect(DestinationApplicationKind.classify(bundleIdentifier: "com.apple.Safari") == .standard)
    #expect(DestinationApplicationKind.classify(bundleIdentifier: nil) == .standard)
}

@Test func corpusURLCanSelectModeWithoutAcceptingOtherCommands() throws {
    let cleanURL = try #require(URL(string: "natter://mode/clean"))
    let legacyURL = try #require(URL(string: "ian-dictation://mode/agent"))
    let unknownURL = try #require(URL(string: "natter://delete/everything"))
    let webURL = try #require(URL(string: "https://example.com/mode/clean"))

    #expect(AppCommand(url: cleanURL) == .setMode(.clean))
    #expect(AppCommand(url: legacyURL) == .setMode(.agent))
    #expect(AppCommand(url: unknownURL) == nil)
    #expect(AppCommand(url: webURL) == nil)
}
