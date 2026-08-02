import DictationCore
import Foundation
import Hub

actor WritingModelInstaller {
    func installAgent(
        in paths: AppPaths,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await install(
            repository: AgentWritingModelLocation.repository,
            revision: AgentWritingModelLocation.revision,
            root: AgentWritingModelLocation.downloadRoot(in: paths),
            progressHandler: progressHandler
        )
    }

    func installQuality(
        in paths: AppPaths,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await install(
            repository: WritingModelLocation.repository,
            revision: WritingModelLocation.revision,
            root: WritingModelLocation.downloadRoot(in: paths),
            progressHandler: progressHandler
        )
    }

    private func install(
        repository: String,
        revision: String,
        root: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let hub = HubApi(downloadBase: root)
        return try await hub.snapshot(
            from: repository,
            revision: revision
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }
    }
}
