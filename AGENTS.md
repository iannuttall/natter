# Agent notes

Natter is a local-only native macOS menu-bar app. It uses Swift 6, SwiftPM,
AppKit lifecycle/panels and SwiftUI views.

## Product rules

- No account, cloud inference, telemetry, Ollama, Homebrew helper or localhost service.
- Speech uses one engine: FluidAudio Parakeet Unified 0.6B — a chunked streaming encoder for the live preview and the full-attention offline encoder for the batch-decoded final transcript.
- Raw is fixed Parakeet output and types after stop. It adds a missing final full stop to prose and otherwise changes only when the user invokes an explicit spoken delivery command.
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
- A release PR must contain the newest signed item at the top of `appcast.xml`. Before opening the PR, build that exact version with `release-app.sh` and stage its notarized DMG and checksum in a private draft GitHub release targeting `main`.
- Never merge a new appcast item without a matching draft release. The `Publish Sparkle release` workflow validates the staged filenames, DMG size and SHA-256 after the appcast lands on `main`, then publishes the draft and creates its tag at the merged commit.
- Do not publish the draft manually before merge. After the workflow passes, confirm the GitHub release is public and use Natter's Check for Updates command against the live feed.
- The required NVIDIA speech model is downloaded only after the user accepts its linked terms. Keep the required attribution in the app and notices.
- Do not bundle model weights into the app.
- GitHub issues are open. Pull request creation is limited to repository collaborators.

## Release PR sequence

```sh
make check

VERSION=0.2.7 \
BUILD_NUMBER=15 \
SIGN_IDENTITY="Developer ID Application: Iancredible Ltd (JXNCT3BEVQ)" \
NOTARY_PROFILE=portmanager \
./scripts/release-app.sh

# Add the printed item to the top of appcast.xml, then stage the artifacts.
gh release create v0.2.7 \
  dist/Natter-0.2.7.dmg \
  dist/Natter-0.2.7.dmg.sha256 \
  --draft \
  --target main \
  --title "Natter 0.2.7" \
  --notes-file RELEASE_NOTES.md
```

Use the next semantic version and a build number greater than the newest appcast item. Commit
the source change separately from `chore(release): prepare VERSION`, push the release branch,
and open a ready PR. Merging the appcast change is the deployment action; the publish workflow
makes the update available to Sparkle without another manual release step.
