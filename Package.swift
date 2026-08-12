// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Natter",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "NatterCore", targets: ["NatterCore"]),
        .executable(name: "Natter", targets: ["NatterApp"]),
        .executable(name: "natter-formatting-bench", targets: ["NatterFormattingBench"]),
        .executable(name: "natter-parity", targets: ["NatterParity"]),
        .executable(name: "natter-asr-eval", targets: ["NatterAsrEval"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            revision: "667181a368da13b3a9178e310414e9dcbe8f23ce"
        ),
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
        .target(name: "NatterCore"),
        .executableTarget(
            name: "NatterApp",
            dependencies: [
                "NatterCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "MLXGuidedGeneration", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ]
        ),
        .executableTarget(
            name: "NatterFormattingBench",
            dependencies: ["NatterCore"]
        ),
        .executableTarget(
            name: "NatterAsrEval",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
        .executableTarget(
            name: "NatterParity",
            dependencies: [
                "NatterCore",
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "MLXGuidedGeneration", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ]
        ),
        .testTarget(
            name: "NatterCoreTests",
            dependencies: ["NatterCore"]
        )
    ]
)
