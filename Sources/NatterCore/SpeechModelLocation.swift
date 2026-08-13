import Foundation

public enum SpeechModelLocation {
    public static let relativePath = "parakeet-unified-en-0.6b"

    private static var requiredModelBundles: [String] {
        [
            "parakeet_unified_encoder_int8.mlmodelc",
            "parakeet_unified_encoder_streaming_\(previewContextSuffix)_int8.mlmodelc",
            "parakeet_unified_decoder.mlmodelc",
            "parakeet_unified_joint_decision_single_step.mlmodelc",
        ]
    }

    /// Streaming preview encoder context: 70 frames left, 7 chunk, 1 right
    /// (560 ms decode cadence, 640 ms theoretical latency). The offline batch
    /// encoder that produces the final transcript has its context baked in.
    public static let previewContextSuffix = "70_7_1"

    public static func installedDirectory(in paths: AppPaths) -> URL {
        paths.models.appendingPathComponent(relativePath, isDirectory: true)
    }

    /// Legacy Nemotron install root, removed when the Parakeet pack installs.
    public static func legacyInstalledRoot(in paths: AppPaths) -> URL {
        paths.models.appendingPathComponent("nemotron-streaming", isDirectory: true)
    }

    public static func resolve(
        in paths: AppPaths,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = environment["DICTATION_SPEECH_MODEL_DIR"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if isComplete(at: url, fileManager: fileManager) { return url }
        }

        let installed = installedDirectory(in: paths)
        return isComplete(at: installed, fileManager: fileManager) ? installed : nil
    }

    public static func isComplete(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let vocab = directory.appendingPathComponent("vocab.json")
        var vocabIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: vocab.path, isDirectory: &vocabIsDirectory),
              !vocabIsDirectory.boolValue else {
            return false
        }

        return requiredModelBundles.allSatisfy { name in
            let bundle = directory.appendingPathComponent(name, isDirectory: true)
            let modelData = bundle.appendingPathComponent("coremldata.bin")
            var modelDataIsDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: modelData.path,
                isDirectory: &modelDataIsDirectory
            ), !modelDataIsDirectory.boolValue else {
                return false
            }

            guard let contents = fileManager.enumerator(
                at: bundle,
                includingPropertiesForKeys: nil
            ) else {
                return false
            }
            return !contents.contains { item in
                (item as? URL)?.pathExtension == "partial"
            }
        }
    }
}
