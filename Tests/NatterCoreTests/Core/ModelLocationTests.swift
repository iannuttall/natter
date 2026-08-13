import Foundation
import Testing

@testable import NatterCore

@Test func speechModelRequiresEveryRuntimeFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let modelBundles = [
        "parakeet_unified_encoder_int8.mlmodelc",
        "parakeet_unified_encoder_streaming_70_7_1_int8.mlmodelc",
        "parakeet_unified_decoder.mlmodelc",
        "parakeet_unified_joint_decision_single_step.mlmodelc",
    ]
    for relativePath in modelBundles {
        let file = directory
            .appendingPathComponent(relativePath, isDirectory: true)
            .appendingPathComponent("coremldata.bin")
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        #expect(FileManager.default.createFile(atPath: file.path, contents: Data()))
    }
    let vocab = directory.appendingPathComponent("vocab.json")
    #expect(FileManager.default.createFile(atPath: vocab.path, contents: Data()))

    #expect(SpeechModelLocation.isComplete(at: directory))
    try FileManager.default.removeItem(at: vocab)
    #expect(!SpeechModelLocation.isComplete(at: directory))
}

@Test func speechModelRejectsAnIncompleteCompiledBundle() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let modelBundles = [
        "parakeet_unified_encoder_int8.mlmodelc",
        "parakeet_unified_encoder_streaming_70_7_1_int8.mlmodelc",
        "parakeet_unified_decoder.mlmodelc",
        "parakeet_unified_joint_decision_single_step.mlmodelc",
    ]
    for relativePath in modelBundles {
        let bundle = directory.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        #expect(FileManager.default.createFile(
            atPath: bundle.appendingPathComponent("coremldata.bin").path,
            contents: Data()
        ))
    }
    #expect(FileManager.default.createFile(
        atPath: directory.appendingPathComponent("vocab.json").path,
        contents: Data()
    ))

    let streamingBundle = directory.appendingPathComponent(
        "parakeet_unified_encoder_streaming_70_7_1_int8.mlmodelc",
        isDirectory: true
    )
    try FileManager.default.removeItem(
        at: streamingBundle.appendingPathComponent("coremldata.bin")
    )
    let partial = streamingBundle
        .appendingPathComponent("weights", isDirectory: true)
        .appendingPathComponent("weight.bin.partial")
    try FileManager.default.createDirectory(
        at: partial.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    #expect(FileManager.default.createFile(atPath: partial.path, contents: Data()))

    #expect(!SpeechModelLocation.isComplete(at: directory))
}

@Test func speechModelRejectsAStalePartialFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let modelBundles = [
        "parakeet_unified_encoder_int8.mlmodelc",
        "parakeet_unified_encoder_streaming_70_7_1_int8.mlmodelc",
        "parakeet_unified_decoder.mlmodelc",
        "parakeet_unified_joint_decision_single_step.mlmodelc",
    ]
    for relativePath in modelBundles {
        let bundle = directory.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        #expect(FileManager.default.createFile(
            atPath: bundle.appendingPathComponent("coremldata.bin").path,
            contents: Data()
        ))
    }
    #expect(FileManager.default.createFile(
        atPath: directory.appendingPathComponent("vocab.json").path,
        contents: Data()
    ))

    let partial = directory
        .appendingPathComponent(modelBundles[0], isDirectory: true)
        .appendingPathComponent("weights", isDirectory: true)
        .appendingPathComponent("weight.bin.partial")
    try FileManager.default.createDirectory(
        at: partial.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    #expect(FileManager.default.createFile(atPath: partial.path, contents: Data()))

    #expect(!SpeechModelLocation.isComplete(at: directory))
}

@Test func modelPackPathsAndSizesAreExplicit() {
    let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/dictation-models"))

    #expect(
        SpeechModelLocation.installedDirectory(in: paths).path
            == "/tmp/dictation-models/Models/parakeet-unified-en-0.6b")
    #expect(
        AgentWritingModelLocation.installedDirectory(in: paths).path
            == "/tmp/dictation-models/Models/agent-writing/models/mlx-community/Qwen3.5-4B-MLX-4bit"
    )
    #expect(
        WritingModelLocation.installedDirectory(in: paths).path
            == "/tmp/dictation-models/Models/writing/models/mlx-community/Qwen3.5-9B-MLX-4bit")
    #expect(ModelPack.agentWriting.downloadSizeBytes > ModelPack.speech.downloadSizeBytes)
    #expect(ModelPack.agentWriting.downloadSizeBytes < ModelPack.writing.downloadSizeBytes)
    #expect(ModelPack.writing.downloadSizeBytes > ModelPack.speech.downloadSizeBytes)
}

@Test func writingModelRequiresWeightsAndMetadata() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    for name in ["config.json", "tokenizer.json", "model.safetensors.index.json"] {
        #expect(
            FileManager.default.createFile(
                atPath: directory.appendingPathComponent(name).path,
                contents: Data()
            ))
    }
    #expect(!WritingModelLocation.isComplete(at: directory))
    #expect(
        FileManager.default.createFile(
            atPath: directory.appendingPathComponent("model-00001-of-00002.safetensors").path,
            contents: Data()
        ))
    #expect(WritingModelLocation.isComplete(at: directory))
}
