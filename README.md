# Dictation

A native, local macOS dictation app. The working product name is temporary.

The app will use FluidAudio Nemotron Streaming 560 ms for live speech and an
optional Qwen 3.5 9B MLX model for Clean, Email, and Article modes. Ollama is
not a runtime dependency.

## Current build stage

The first executable verifies that Qwen runs directly through MLX Swift with
the same writing fixtures used during model selection. MLX's Metal shaders
must be built by Xcode, so use the checked-in runner rather than `swift run`:

```sh
./scripts/run-parity.sh
```

Pure Swift logic remains testable with `swift test`.

