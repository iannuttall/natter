# Agent notes

Dictation is a local-only native macOS menu-bar app. It uses Swift 6, SwiftPM,
AppKit lifecycle/panels and SwiftUI views. The working product name is temporary.

## Product rules

- No account, cloud inference, telemetry, Ollama, Homebrew helper or localhost service.
- Speech uses one engine: FluidAudio Nemotron Streaming 560 ms.
- Raw and Agent modes type stable text incrementally.
- Clean, Email and Article transform only after stop with optional local Qwen.
- Raw text must survive every insertion or transformation failure.
- Models live under Application Support and are never bundled in the signed app.

## Repo map

```text
Sources/DictationCore/   pure models, rules and testable pipeline logic
Sources/DictationApp/    AppKit lifecycle/services and SwiftUI views
Sources/DictationParity/ direct MLX writing benchmark
Tests/                   pure logic tests
scripts/                 build and benchmark entry points
```

## Commands

```sh
swift test
swift build -c release --product dictation
./scripts/build-app.sh
./scripts/run-parity.sh
```

## MLX packaging

`swift build` does not compile MLX's Metal shaders. Any target that links MLX
for production must be built with `xcodebuild` and include
`mlx-swift_Cmlx.bundle` beside the executable. The parity runner already does
this. The app build script uses the same Xcode path and copies every generated
resource bundle into `Contents/Resources` before signing. Do not replace that
production build with a plain `swift build` invocation.
