# Direct MLX Swift parity

Tested on Ian's M3 Max against the same fixtures previously run through the
Ollama-hosted Qwen 3.5 9B MLX package.

## Decision

Use MLX Swift directly in the app. Ollama is not a product dependency.

The pinned Hugging Face checkpoint is
`mlx-community/Qwen3.5-9B-MLX-4bit@938d8919941c6e7efd3c7150eff7fe9d12afa631`.
Its files total 5.95 GB, versus 8.9 GB for the Ollama NVFP4 package.

| Package | Required facts | Forbidden removed | Reference edit | Warm p50 | Long stress |
| --- | ---: | ---: | ---: | ---: | ---: |
| Direct MLX Swift, affine 4-bit | 94.6% | 95.2% | 19.3% | 1.03 s | 7.18 s |
| Ollama MLX NVFP4 benchmark | 96.4% | 92.9% | 19.5% | 1.03 s | 7.53 s |

The direct checkpoint preserved every checked fact in the 4,328-token stress
case. One apparent short-fixture miss was only `70` rendered as `seventy`.
The meaningful regression was dropping `probably` from one Clean fixture and
retaining the opening `Um` in the long stress case. Deterministic uncertainty
protection and filler removal belong around the model in either runtime.

## Packaging finding

`swift build` compiles MLX's Swift/C++ code but cannot compile its Metal shader
library. Production builds must use `xcodebuild`, which embeds
`mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib`. The app build must
copy that resource bundle beside the executable inside the signed app.

