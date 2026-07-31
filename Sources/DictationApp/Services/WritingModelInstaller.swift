import DictationCore
import Foundation
import Hub

actor WritingModelInstaller {
    func install(
        in paths: AppPaths,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let root = WritingModelLocation.downloadRoot(in: paths)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let hub = HubApi(downloadBase: root)
        return try await hub.snapshot(
            from: WritingModelLocation.repository,
            revision: WritingModelLocation.revision
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }
    }
}
