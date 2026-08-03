import Foundation

public enum ModelPack: String, CaseIterable, Identifiable, Sendable {
    case speech
    case agentWriting
    case writing

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .speech: "Live speech"
        case .agentWriting: "Fast Agent cleanup"
        case .writing: "Long-form writing"
        }
    }

    public var detail: String {
        switch self {
        case .speech: "Parakeet Unified 0.6B · required"
        case .agentWriting: "Qwen 3.5 4B MLX 4-bit · guarded run-on cleanup"
        case .writing: "Qwen 3.5 9B MLX 4-bit · Email and Article"
        }
    }

    public var downloadSizeBytes: Int64 {
        switch self {
        case .speech: 1_160_000_000
        case .agentWriting: 3_030_000_000
        case .writing: 5_950_000_000
        }
    }

    public var sizeLabel: String {
        switch self {
        case .speech: "1.16 GB"
        case .agentWriting: "3.03 GB"
        case .writing: "5.95 GB"
        }
    }
}

public enum AgentWritingModelLocation {
    public static let repository = "mlx-community/Qwen3.5-4B-MLX-4bit"
    public static let revision = "32f3e8ecf65426fc3306969496342d504bfa13f3"

    public static func downloadRoot(in paths: AppPaths) -> URL {
        paths.models.appendingPathComponent("agent-writing", isDirectory: true)
    }

    public static func installedDirectory(in paths: AppPaths) -> URL {
        downloadRoot(in: paths)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("mlx-community", isDirectory: true)
            .appendingPathComponent("Qwen3.5-4B-MLX-4bit", isDirectory: true)
    }

    public static func resolve(
        in paths: AppPaths,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = environment["DICTATION_AGENT_WRITING_MODEL_DIR"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if WritingModelLocation.isComplete(at: url, fileManager: fileManager) { return url }
        }
        let installed = installedDirectory(in: paths)
        return WritingModelLocation.isComplete(at: installed, fileManager: fileManager)
            ? installed
            : nil
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

    public static func resolve(
        in paths: AppPaths,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = environment["DICTATION_WRITING_MODEL_DIR"], !override.isEmpty {
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
