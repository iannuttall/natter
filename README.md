# Dictation

A native, local macOS dictation app. The working product name is temporary.

Dictation uses FluidAudio Nemotron Streaming 560 ms for live speech and an
optional Qwen 3.5 9B model through MLX Swift for Email and Article. It has no
account, cloud inference, telemetry, Ollama dependency or background server.

## Use it

1. Build and launch the signed app:

   ```sh
   ./scripts/build-app.sh
   open dist/Dictation.app
   ```

2. In Settings, allow Microphone, Accessibility and Input Monitoring.
3. Download the required 613 MB **Live speech** model. Download the optional
   5.95 GB **Writing tools** model only if you want Email or Article.
4. Quit Monologue while testing because it uses the same global shortcut.
5. Focus an editable field, double-tap Right Option to start, then tap Right
   Option once to stop. Right Control can be selected in Settings instead.

The menu-bar menu changes mode and can copy the last completed transcript.
Settings opens automatically whenever a required permission or the speech model
is missing.

## Modes

- **Raw** types stable phrases live and applies personal corrections.
- **Agent** types stable phrases live for terminal and coding-agent prompts.
- **Clean** removes explicit filler and obvious repeated words or phrases after
  stop, without another model.
- **Email** formats a direct email body after stop.
- **Article** restructures longer speech into prose after stop.

Only append-only stable phrases are sent to the focused app. Mutable guesses
remain in the non-activating overlay. Text is inserted as small Unicode keyboard
events rather than through the clipboard. Known terminal apps receive paced
chunks so coding-agent TUIs do not merge a long transcript into one paste burst.
Terminal pacing is enabled by default and can be disabled in Settings.

The app captures the frontmost process and focused Accessibility element when a
session starts. If focus changes, insertion fails or a writing result drops a
protected fact, the complete intended transcript is copied to the clipboard and
saved under:

```text
~/Library/Application Support/is.ian.dictation/Recovery/latest.json
```

## Personal rules

Settings opens a native editor for local Markdown files under:

```text
~/Library/Application Support/is.ian.dictation/Rules/
```

`personal.md` stores deterministic corrections. The other files hold the Clean,
Email and Article instructions. A correction can also be taught by voice:

> Hey Dictation, you just transcribed it as port man but what I actually said
> was Portman p-o-r-t-m-a-n can you add that to my rules so you remember for
> next time.

The command is not typed into the destination. It is parsed locally and saved
to the same reversible Markdown file.

## Product corpus

The local browser harness covers 21 delivery, recovery, correction, writing and
stress scenarios. It switches modes, captures and grades output, saves results
to disk and advances automatically. It deliberately does not repeat accent/model
selection; the recorded benchmark already tested Ian's British accent.

```sh
./scripts/serve-product-corpus.sh
```

Open `http://127.0.0.1:4173` and press **Start run**. Results are written after
every scenario to `ProductCorpus/Results/latest.json`.

## Build and verification

```sh
swift test
./scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 dist/Dictation.app
./scripts/run-parity.sh
node --test ProductCorpus/tests/scenarios.test.mjs
```

`build-app.sh` uses Xcode rather than `swift build` so MLX's Metal shaders are
compiled and copied into the signed app. Model weights are never bundled in the
app; they live under Application Support and are installed through Settings.
The script uses the first local code-signing identity by default so macOS keeps
Microphone, Accessibility and Input Monitoring trust across development builds.
Set `SIGN_IDENTITY` to choose a different certificate.

The direct MLX parity report is in `Results/direct-mlx-parity.md`. The pinned
Qwen checkpoint is:

```text
mlx-community/Qwen3.5-9B-MLX-4bit@938d8919941c6e7efd3c7150eff7fe9d12afa631
```

## Repository map

```text
Sources/DictationCore/   pure models, rules and pipeline logic
Sources/DictationApp/    native lifecycle, services and SwiftUI/AppKit UI
Sources/DictationParity/ direct MLX writing benchmark
Tests/                   pure Swift regression tests
ProductCorpus/           local workflow test harness
scripts/                 build, parity and corpus entry points
```
