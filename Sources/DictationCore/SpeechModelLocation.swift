import Foundation

public enum SpeechModelLocation {
    public static let relativePath = "nemotron-streaming/560ms"

    public static func installedDirectory(in paths: AppPaths) -> URL {
        paths.models.appendingPathComponent(relativePath, isDirectory: true)
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
        let requiredPaths = [
            "encoder/encoder_int8.mlmodelc",
            "decoder.mlmodelc",
            "joint.mlmodelc",
            "tokenizer.json"
        ]
        return requiredPaths.allSatisfy {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }
}
