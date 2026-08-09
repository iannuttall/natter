<div align="center">

<img src="docs/assets/n-wave-cyan.svg" width="150" alt="Natter">

# Natter

**Fast dictation for people who talk in code, commands, and half-finished thoughts.**

Natter is a native macOS menu bar app that transcribes speech locally, cleans it up, and
types into the app you were already using.

[Download for macOS](https://github.com/iannuttall/natter/releases/latest) ·
[Report a problem](https://github.com/iannuttall/natter/issues) · Apache 2.0 licensed

</div>

---

## What Natter does

Double-tap Right Option and start talking. Natter listens through a local speech model and
shows the live transcript in a small overlay. Tap Right Option once to stop.

Raw shows Parakeet's direct transcript in the overlay, adds a missing final full stop to prose,
then types it after you stop. Every
other mode shares Natter's deterministic cleanup for fillers, repetitions, punctuation and
technical terms. Each mode then chooses Fast, Refine or Rewrite processing. Press Tab while
listening to switch mode without moving focus out of the text field. Double-tap Left Option to
cancel a recording.

The app is designed for the awkward dictation that ordinary macOS speech tools tend to
mangle: GitHub, SwiftPM, `--flags`, file paths, version numbers, terminal commands, and names
from your own dictionary.

## Nothing you say leaves your Mac

There is no account, cloud transcription, telemetry, Ollama dependency, Homebrew helper, or
localhost service. Audio and transcripts stay on the Mac.

Natter downloads model weights only after you choose to install them. They live under
Application Support and are never bundled into the app or this repository.

| Model | Used for | Download |
|---|---|---:|
| FluidAudio Parakeet Unified 0.6B | Required live speech | 1.16 GB |
| Qwen 3.5 4B MLX 4-bit | Optional Refine processing | 3.03 GB |
| Qwen 3.5 9B MLX 4-bit | Optional Rewrite processing | 5.95 GB |

Fast never uses a writing model. Refine falls back to deterministic cleanup when its optional
4B model is unavailable or rejects an unsafe edit. Rewrite requires the optional 9B model.

## Dictation modes

- **Raw** is fixed. It types the final Parakeet transcript after stop with no cleanup or technical
  formatting, adding only a missing final full stop to prose.
- **Agent** starts as a Fast mode for low-latency technical dictation.
- **Clean** starts as a Refine mode for guarded punctuation and flow improvements.
- **Email** and **Article** start as Rewrite modes with instructions suited to each format.

The preset modes can be renamed, reordered, edited or hidden. You can also add your own modes.
Each editable mode chooses one processing level:

- **Fast** applies shared deterministic cleanup only.
- **Refine** asks the local 4B model to improve punctuation and flow without changing meaning.
- **Rewrite** asks the local 9B model to restructure the transcript using that mode's editable
  instructions.

Every delivery path keeps the original transcript recoverable. If the destination loses
focus, rejects keyboard events, or a model returns an unsafe rewrite, Natter stores a local
recovery record and copies the complete intended transcript.

## Install Natter

Download the latest DMG, drag Natter to Applications, and launch it. Natter supports Apple
silicon Macs running macOS 15 or later.

The setup assistant walks through three macOS permissions:

- Microphone lets Natter hear the active recording.
- Accessibility lets it identify the text field that had focus.
- Input Monitoring lets the global dictation shortcut work outside Natter.

The app can open at login. You can change that from Settings at any time.

## Teach it your words

The dictionary stores preferred spellings locally. Writing rules are plain Markdown files
under:

```text
~/Library/Application Support/is.ian.natter/Rules/
```

You can also teach a correction by voice:

> Hey Natter, you just transcribed it as port man but what I said was Portman,
> p-o-r-t-m-a-n. Add that to my rules.

The correction command is consumed instead of being typed into the destination.

## Verify a downloaded build

Public builds are signed with Developer ID and notarized by Apple.

```sh
codesign --verify --deep --strict --verbose=2 /Applications/Natter.app
spctl --assess --type execute --verbose=4 /Applications/Natter.app
```

Each GitHub release also includes a SHA-256 checksum for its DMG.

```sh
shasum -a 256 ~/Downloads/Natter-*.dmg
```

## Build it locally

```sh
make check       # Swift and product-corpus tests
make build       # signed app in dist/Natter.app
make install     # install to ~/Applications and enable Open at Login
make dmg         # drag-install DMG
make parity      # direct MLX writing benchmark
```

`build-app.sh` uses Xcode because MLX Metal shaders are not compiled by a plain SwiftPM
release build. The script copies every generated resource bundle and Sparkle framework into
the signed app before verification.

The main source areas are:

```text
Sources/NatterCore/   pure models, rules, and pipeline logic
Sources/NatterApp/    AppKit lifecycle, services, and SwiftUI views
Sources/NatterParity/ direct MLX writing benchmark
Tests/                   pure Swift regression tests
ProductCorpus/           local workflow test harness
scripts/                 build, install, release, and benchmark commands
```

Read [AGENTS.md](AGENTS.md) before changing the app. It records the product contracts and
build traps that are easy to reintroduce.

## Report bugs and request features

Open a [GitHub issue](https://github.com/iannuttall/natter/issues) with the macOS version,
destination app, selected mode, and what happened to the transcript. Pull request creation is
limited to maintainers so fixes can stay tied to the local safety and release checks.

## License

Natter is licensed under Apache License 2.0. Model weights keep their original upstream
licences and are downloaded separately after their terms are shown in the app. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the full attribution list.
