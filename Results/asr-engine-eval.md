# ASR engine evaluation — Nemotron 560 ms vs Parakeet Unified vs SpeechAnalyzer

Date: 2026-08-03. Hardware: this development Mac (Apple silicon, macOS 26).
Harness: `dictation-asr-eval` (release build), dataset built by
`scripts/prepare-asr-eval-data.py` from LibriSpeech test-clean: 20 short
utterances (2–8 s), 20 medium (8–20 s), 8 long (~60 s same-chapter
concatenations), 4 extra-long (~150 s). Every file was upsampled once to
48 kHz mono WAV so each engine sees mic-like input and performs its own
conversion, matching the app's capture path. WER is computed on normalized
text (lowercased, punctuation stripped), so punctuation quality is not
penalized. Stop→final is the time from the stop request to the final
transcript, the latency the user actually feels before post-processing.

## Results

| Engine / pipeline | Agg WER | short WER | medium WER | long WER | xlong WER | stop→final p50 | stop→final max |
|---|---:|---:|---:|---:|---:|---:|---:|
| Nemotron 560 ms stream (previous pipeline) | 3.15% | 2.12% | 1.94% | 4.62% | 2.54% | 26 ms | 41 ms |
| Nemotron 560 ms + stateful resampler | 3.03% | 2.12% | 1.94% | 4.41% | 2.43% | 26 ms | 33 ms |
| Parakeet Unified stream 70_7_1 (new preview) | 2.74% | 0.85% | 1.76% | 4.27% | 2.11% | 18 ms | 23 ms |
| Parakeet Unified stream 70_2_2 | 2.64% | 1.27% | 1.59% | 4.27% | 1.90% | 17 ms | 21 ms |
| Parakeet Unified batch at stop (new pipeline) | 2.33% | 0.42% | 2.12% | 3.85% | 1.48% | 74 ms | 1168 ms |
| Apple SpeechAnalyzer (macOS 26) | 2.28% | 1.69% | 1.76% | 3.15% | 1.85% | 216 ms | 3377 ms |

## Conclusions

- **Parakeet Unified batch cuts aggregate WER 26% relative vs the shipping
  Nemotron pipeline** (3.15% → 2.33%), and 80% relative on short dictations
  (2.12% → 0.42%), the most common case. Its stop→final cost is 74 ms median
  and 1.2 s worst case on a 2.5-minute dictation — imperceptible next to the
  insertion path and far below Monologue Local's recorded 3.2–6.4 s
  stop-to-text timings.
- **The stateless per-buffer resampler was a real accuracy bug**: keeping the
  same Nemotron engine and only converting with one stateful converter
  improved WER 3.15% → 3.03%. The capture path now converts to 16 kHz mono
  once, with one long-lived converter.
- **Apple SpeechAnalyzer is accurate but finalizes slowly on long audio**
  (1.2 s at 60 s, 2.9–3.4 s at 150 s — worse than the whole new pipeline) and
  loses clearly to Unified batch on short dictations (1.69% vs 0.42%). It also
  requires macOS 26 while Natter supports macOS 15, offers no custom-vocabulary
  path, and would break the local-model contract's control over updates. Not
  adopted; revisit if the deployment target ever moves.
- **Preview tier**: both Unified streaming exports beat Nemotron. The app uses
  70_7_1 (560 ms decode cadence — same as before, 640 ms theoretical latency)
  because it re-encodes ~11x less audio per second than 70_2_2 for the same
  overlay purpose; final text comes from the batch pass either way.
- The `long` bucket is noisier than `xlong` for every engine (same two
  chapters dominate); relative comparisons are unaffected because all engines
  saw identical audio.

## Reproduce

```sh
python3 scripts/prepare-asr-eval-data.py     # in a directory with LibriSpeech/test-clean
swift build -c release --product dictation-asr-eval
.build/release/dictation-asr-eval --mode unified-batch \
  --manifest manifest.json --output results-unified-batch.json
```

Modes: `nemotron-stream`, `nemotron-stream-16k`, `unified-batch`,
`unified-stream-322`, `unified-stream-771`, `speechanalyzer`. The Nemotron
modes need the old model pack installed (`--nemotron-dir`); Unified modes
default to the FluidAudio cache (`--unified-dir` to override).
