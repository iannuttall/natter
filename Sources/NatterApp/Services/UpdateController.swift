import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class UpdateController {
    static let shared = UpdateController()

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private let windowObserver = UpdateWindowObserver()

    private(set) var pendingUpdate: String?

    var isConfigured: Bool {
        controller != nil
    }

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    private init() {
        guard Self.feedURL != nil, Self.publicKey != nil else { return }

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: windowObserver
        )
        windowObserver.foundQuietUpdate = { [weak self] version in
            self?.pendingUpdate = version
        }
        windowObserver.didFinishSession = { [weak self] in
            self?.pendingUpdate = nil
        }
    }

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }

    private static var feedURL: String? {
        value(for: "SUFeedURL")
    }

    private static var publicKey: String? {
        value(for: "SUPublicEDKey")
    }

    private static func value(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.hasPrefix("REPLACE_") else {
            return nil
        }
        return value
    }
}

private final class UpdateWindowObserver: NSObject, SPUStandardUserDriverDelegate, @unchecked Sendable {
    var foundQuietUpdate: (@MainActor (String) -> Void)?
    var didFinishSession: (@MainActor () -> Void)?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        MainActor.assumeIsolated {
            foundQuietUpdate?(update.displayVersionString)
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            didFinishSession?()
        }
    }
}
