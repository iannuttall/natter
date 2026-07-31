# Dictation

A native, local macOS dictation app. The working product name is temporary.

The app will use FluidAudio Nemotron Streaming 560 ms for live speech and an
optional Qwen 3.5 9B MLX model for Clean, Email, and Article modes. Ollama is
not a runtime dependency.

## Current build stage

The native menu-bar shell, shared state, mode picker and Settings window are
buildable now:

```sh
swift test
./scripts/build-app.sh
DICTATION_OPEN_ON_LAUNCH=1 dist/Dictation.app/Contents/MacOS/dictation
```

The parity executable verifies that Qwen runs directly through MLX Swift with
the same writing fixtures used during model selection. MLX's Metal shaders
must be built by Xcode, so use the checked-in runner rather than `swift run`:

```sh
./scripts/run-parity.sh
```

Pure Swift logic remains testable with `swift test`.

