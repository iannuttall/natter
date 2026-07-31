import Foundation

public enum ModelPack: String, CaseIterable, Identifiable, Sendable {
    case speech
    case writing

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .speech: "Live speech"
        case .writing: "Writing tools"
        }
    }

    public var detail: String {
        switch self {
        case .speech: "Nemotron Streaming 560 ms · required"
        case .writing: "Qwen 3.5 9B MLX 4-bit · optional"
        }
    }

    public var downloadSizeBytes: Int64 {
        switch self {
        case .speech: 613_000_000
        case .writing: 5_950_000_000
        }
    }

    public var sizeLabel: String {
        switch self {
        case .speech: "613 MB"
        case .writing: "5.95 GB"
        }
    }
}

public enum WritingModelLocation {
    public static let repository = "mlx-community/Qwen3.5-9B-MLX-4bit"
    public static let revision = "938d8919941c6e7efd3c7150eff7fe9d12afa631"

    public static func downloadRoot(in paths: AppPaths) -> URL {
        paths.models.appendingPathComponent("writing", isDirectory: true)
    }

    public static func installedDirectory(in paths: AppPaths) -> URL {
        downloadRoot(in: paths)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("mlx-community", isDirectory: true)
            .appendingPathComponent("Qwen3.5-9B-MLX-4bit", isDirectory: true)
    }

    public static func isComplete(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let required = ["config.json", "tokenizer.json", "model.safetensors.index.json"]
        guard required.allSatisfy({
            fileManager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }) else { return false }

        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.contains { $0.pathExtension == "safetensors" }
    }
}
