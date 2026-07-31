// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "dictation",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "DictationCore", targets: ["DictationCore"]),
        .executable(name: "dictation-parity", targets: ["DictationParity"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm.git",
            revision: "a2736d4ea9472af8809a0b278c294aaf1f0918ba"
        ),
        .package(
            url: "https://github.com/huggingface/swift-transformers.git",
            revision: "0d7842981ff6156c05aebedf23459a780b22c624"
        )
    ],
    targets: [
        .target(name: "DictationCore"),
        .executableTarget(
            name: "DictationParity",
            dependencies: [
                "DictationCore",
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ]
        ),
        .testTarget(
            name: "DictationCoreTests",
            dependencies: ["DictationCore"]
        )
    ]
)
