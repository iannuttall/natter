# Dictation

A native, local macOS dictation app. The working product name is temporary.

Dictation uses FluidAudio Nemotron Streaming 560 ms for live speech and an
optional Qwen 3.5 9B model through MLX Swift for Agent, Email and Article. It has no
account, cloud inference, telemetry, Ollama dependency or background server.

The app currently targets Apple silicon Macs running macOS 15 or later. The
signed app is about 88 MB installed and 27 MB as a release ZIP. Models are
downloaded separately during onboarding.

## Use it

1. Build and launch the signed app:

   ```sh
   ./scripts/build-app.sh
   open dist/Dictation.app
   ```

2. Follow the setup assistant. It installs the required 613 MB **Live speech**
   model, explains Microphone, Accessibility and Input Monitoring, and verifies
   the shortcut in a real text field.
3. Download the optional 5.95 GB **Writing tools** model only if you want local
   AI cleanup for Agent, Email or Article. Raw and Clean do not need it.
4. Quit Monologue while testing because it uses the same global shortcut.
5. Focus an editable field, double-tap Right Option to start, then tap Right
   Option once to stop. Hold Right Option while idle to cycle modes and show the
   selected mode. Right Control can be selected in Settings instead.

The menu-bar menu changes mode, opens local history, copies the last completed
transcript and exposes setup, privacy and licence details. The setup assistant
opens automatically whenever a required permission or the speech model is
missing.

## Modes

- **Raw** types stable phrases live and applies personal corrections.
- **Agent** shows the live transcript in the overlay, applies conservative local technical formatting when you stop, then types the result visibly. Live Agent typing remains an advanced option.
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
protected fact, the undelivered tail is copied when it can be identified;
otherwise the complete intended transcript is copied. The complete recovery
record is saved under:

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

The local browser harness covers delivery, recovery, correction, writing and
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

For a Developer ID archive and notarized public release, see
[`docs/RELEASING.md`](docs/RELEASING.md). Application and dependency licences
are bundled under `Contents/Resources/Legal` and available from **About &
Legal** in the app.

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
