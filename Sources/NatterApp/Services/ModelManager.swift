import NatterCore
import FluidAudio
import Foundation
import Observation

@MainActor
@Observable
final class ModelManager {
    private let paths: AppPaths
    private let speechTranscriber: SpeechTranscriber
    private let writingInstaller = WritingModelInstaller()
    private var installationTask: Task<Void, Never>?
    private var speechWarmupTask: Task<Void, Never>?

    private(set) var speechInstalled = false
    private(set) var agentWritingInstalled = false
    private(set) var writingInstalled = false
    private(set) var installing: ModelPack?
    private(set) var progress: Double = 0
    private(set) var status = ""
    private(set) var errorMessage: String?

    init(
        paths: AppPaths = .live(bundleIdentifier: AppInfo.bundleIdentifier),
        speechTranscriber: SpeechTranscriber
    ) {
        self.paths = paths
        self.speechTranscriber = speechTranscriber
        refresh()
    }

    func isInstalled(_ pack: ModelPack) -> Bool {
        switch pack {
        case .speech: speechInstalled
        case .agentWriting: agentWritingInstalled
        case .writing: writingInstalled
        }
    }

    func install(_ pack: ModelPack) {
        guard installing == nil else { return }
        installing = pack
        progress = 0
        status = "Preparing download…"
        errorMessage = nil

        installationTask = Task {
            do {
                try ensureDiskSpace(for: pack)
                switch pack {
                case .speech:
                    try await installSpeech()
                case .agentWriting:
                    try await installAgentWriting()
                case .writing:
                    try await installWriting()
                }
                refresh()
                progress = 1
                status = "Installed"
                installing = nil
                installationTask = nil
            } catch is CancellationError {
                errorMessage = nil
                status = "Download paused"
                installing = nil
                installationTask = nil
            } catch {
                errorMessage = error.localizedDescription
                status = "Download failed"
                installing = nil
                installationTask = nil
            }
        }
    }

    func cancelInstallation() {
        guard installing != nil else { return }
        installationTask?.cancel()
        status = "Stopping download…"
    }

    func warmSpeechModelIfInstalled() {
        guard speechInstalled, speechWarmupTask == nil else { return }
        let directory = SpeechModelLocation.installedDirectory(in: paths)
        speechWarmupTask = Task {
            let startedAt = ProcessInfo.processInfo.systemUptime
            do {
                try await speechTranscriber.prepare(modelDirectory: directory)
                let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                NatterLog.model.notice(
                    "speech model warm elapsed_ms=\(String(format: "%.1f", milliseconds), privacy: .public)"
                )
            } catch is CancellationError {
                NatterLog.model.debug("speech model warm-up cancelled")
            } catch {
                NatterLog.model.error(
                    "speech model warm-up failed error=\(error.localizedDescription, privacy: .public)"
                )
            }
            speechWarmupTask = nil
        }
    }

    func remove(_ pack: ModelPack) {
        guard installing == nil else { return }
        errorMessage = nil

        do {
            switch pack {
            case .speech:
                speechWarmupTask?.cancel()
                speechWarmupTask = nil
                try removeIfPresent(SpeechModelLocation.installedDirectory(in: paths))
                Task { await speechTranscriber.unload() }
            case .writing:
                try removeIfPresent(WritingModelLocation.downloadRoot(in: paths))
            case .agentWriting:
                try removeIfPresent(AgentWritingModelLocation.downloadRoot(in: paths))
            }
            refresh()
            status = "Removed"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() {
        speechInstalled = SpeechModelLocation.isComplete(
            at: SpeechModelLocation.installedDirectory(in: paths)
        )
        agentWritingInstalled = WritingModelLocation.isComplete(
            at: AgentWritingModelLocation.installedDirectory(in: paths)
        )
        writingInstalled = WritingModelLocation.isComplete(
            at: WritingModelLocation.installedDirectory(in: paths)
        )
    }

    private func installSpeech() async throws {
        status = "Downloading live speech…"
        try await speechTranscriber.install(to: paths.models) { [weak self] progress in
            Task { @MainActor in
                self?.progress = progress.fractionCompleted
                self?.status = Self.label(for: progress.phase)
            }
        }
        // A pre-Parakeet install leaves the old Nemotron pack orphaned on disk.
        try? removeIfPresent(SpeechModelLocation.legacyInstalledRoot(in: paths))
    }

    private func installWriting() async throws {
        status = "Downloading long-form writing…"
        let directory = try await writingInstaller.installQuality(in: paths) { [weak self] progress in
            Task { @MainActor in self?.progress = progress }
        }
        guard WritingModelLocation.isComplete(at: directory) else {
            throw ModelManagerError.incompleteDownload
        }
    }

    private func installAgentWriting() async throws {
            status = "Downloading Refine output model…"
        let directory = try await writingInstaller.installAgent(in: paths) { [weak self] progress in
            Task { @MainActor in self?.progress = progress }
        }
        guard WritingModelLocation.isComplete(at: directory) else {
            throw ModelManagerError.incompleteDownload
        }
    }

    private func ensureDiskSpace(for pack: ModelPack) throws {
        let values = try paths.root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage,
           available < pack.downloadSizeBytes + 1_000_000_000 {
            throw ModelManagerError.insufficientDiskSpace(pack.sizeLabel)
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func label(for phase: DownloadPhase) -> String {
        switch phase {
        case .listing: "Checking model files…"
        case let .downloading(completed, total):
            total > 0 ? "Downloading file \(completed + 1) of \(total)…" : "Checking local files…"
        case let .compiling(modelName):
            modelName.isEmpty ? "Finishing…" : "Preparing \(modelName)…"
        }
    }
}

enum ModelManagerError: LocalizedError {
    case incompleteDownload
    case insufficientDiskSpace(String)

    var errorDescription: String? {
        switch self {
        case .incompleteDownload:
            "The model download finished without every required file."
        case let .insufficientDiskSpace(size):
            "Not enough free space for the \(size) model pack."
        }
    }
}
