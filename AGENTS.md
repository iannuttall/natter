# Agent notes

Natter is a local-only native macOS menu-bar app. It uses Swift 6, SwiftPM,
AppKit lifecycle/panels and SwiftUI views.

## Product rules

- No account, cloud inference, telemetry, Ollama, Homebrew helper or localhost service.
- Speech uses one engine: FluidAudio Parakeet Unified 0.6B — a chunked streaming encoder for the live preview and the full-attention offline encoder for the batch-decoded final transcript.
- Raw is fixed, untouched Parakeet output and types after stop.
- Every non-Raw mode shares deterministic cleanup for fillers, repetitions, punctuation and technical terms.
- Editable modes choose Fast, Refine or Rewrite processing. Fast stops after deterministic cleanup. Refine uses the optional local Qwen 3.5 4B model with guarded output. Rewrite uses the optional local Qwen 3.5 9B model and editable instructions.
- Agent, Clean, Email and Article are editable presets. Users may hide them or add, reorder and delete custom modes. Advanced live Agent delivery remains optional.
- Raw text must survive every insertion or transformation failure.
- Models live under Application Support and are never bundled in the signed app.
- History, stats, rules and app profiles are local. Do not add telemetry without an explicit product decision and an opt-in design.

## Repo map

```text
Sources/NatterCore/   pure models, rules and testable pipeline logic
Sources/NatterApp/    AppKit lifecycle/services and SwiftUI views
Sources/NatterParity/ direct MLX writing benchmark
Tests/                   pure logic tests
scripts/                 build and benchmark entry points
.github/                 public CI and project metadata
```

## Commands

```sh
swift test
swift build -c release --product Natter
make check
make install
./scripts/build-app.sh
VERSION=0.1.0 BUILD_NUMBER=1 ./scripts/release-app.sh
./scripts/run-parity.sh
```

## MLX packaging

`swift build` does not compile MLX's Metal shaders. Any target that links MLX
for production must be built with `xcodebuild` and include
`mlx-swift_Cmlx.bundle` beside the executable. The parity runner already does
this. The app build script uses the same Xcode path and copies every generated
resource bundle into `Contents/Resources` before signing. Do not replace that
production build with a plain `swift build` invocation.

## Release shape

- Apple silicon and macOS 15 or later for now.
- Public builds use Developer ID, hardened runtime, notarization and stapling.
- Sparkle updates use the pinned appcast URL and EdDSA public key in `build-app.sh`. Never rotate either after the first release without a migration plan.
- `release-app.sh` requires `VERSION` and `BUILD_NUMBER`; set `NOTARY_PROFILE` for a public archive.
- The required NVIDIA speech model is downloaded only after the user accepts its linked terms. Keep the required attribution in the app and notices.
- Do not bundle model weights into the app.
- GitHub issues are open. Pull request creation is limited to repository collaborators.
