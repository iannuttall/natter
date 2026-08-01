# Third-party notices

Dictation is licensed under Apache License 2.0. The complete application licence and dependency licence files are included in the signed app under `Contents/Resources/Legal`.

## Runtime packages

The pinned revisions are recorded in `Package.resolved`.

### Apache License 2.0

- FluidAudio — FluidInference
- swift-transformers — Hugging Face
- swift-huggingface — Hugging Face
- swift-jinja — Hugging Face
- swift-argument-parser — Apple
- swift-asn1 — Apple
- swift-atomics — Apple
- swift-collections — Apple
- swift-crypto — Apple
- swift-nio — Apple
- swift-numerics — Apple
- swift-syntax — Swift.org
- swift-system — Apple

The upstream NOTICE files supplied by SwiftASN1, SwiftCrypto and SwiftNIO are reproduced with their licence files in the app bundle.

### MIT License

- EventSource — Copyright 2025 Mattt
- MLX Swift — Copyright 2023 ml-explore
- MLX Swift LM — Copyright 2024 ml-explore
- yyjson — Copyright 2020 YaoYuan

Their complete MIT licence texts are reproduced in the app bundle.

## Downloaded model weights

Model weights are not bundled in Dictation.app. The app downloads them on the user's explicit request and stores them under the app's Application Support directory.

### Nemotron Speech Streaming 0.6B Core ML

- Model: `FluidInference/nemotron-speech-streaming-en-0.6b-coreml`
- Licence: NVIDIA Open Model License Agreement, last modified 24 October 2025
- Licence: https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/
- Trustworthy AI terms: https://www.nvidia.com/en-us/agreements/trustworthy-ai/terms/

Licensed by NVIDIA Corporation under the NVIDIA Open Model License

### Qwen 3.5 9B MLX 4-bit

- Model: `mlx-community/Qwen3.5-9B-MLX-4bit`
- Original model: `Qwen/Qwen3.5-9B`
- Licence: Apache License 2.0
- Model card: https://huggingface.co/mlx-community/Qwen3.5-9B-MLX-4bit

## Privacy

Dictation has no account, analytics endpoint or cloud inference. Audio, transcripts, rules, app profiles, history and models stay on the user's Mac unless the user explicitly copies or exports them.
