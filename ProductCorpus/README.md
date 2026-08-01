# Product corpus

This local browser harness tests the behaviour around the chosen speech and writing models. It does not repeat the model-selection or accent benchmark.

Run it from the repository root:

```sh
./scripts/serve-product-corpus.sh
```

Open `http://127.0.0.1:4173`, launch the native Dictation app, and press **Start run** once. The runner selects each mode through a local app URL, focuses the field, recognises the Right Option or Right Control start/stop sequence, captures input timing, grades the settled result and advances automatically.

Quit Monologue before a run because it uses the same double Right Option shortcut. After starting, only use the native hotkey and read the displayed script exactly. There are no checkboxes, notes or export step.

Email and Article scenarios are saved as skipped when their optional Writing tools model is not installed, so the rest of the run can continue without waiting.

For a targeted regression run, pass comma-separated scenario IDs in `?only=`, for example `?only=raw-protected-facts,clean-facts`.

Open `http://127.0.0.1:4173/writing` for the guided formatting and writing-mode run. It contains ten short Agent, Clean, Email and Article tests. If the optional Writing Tools download is still running when the wizard reaches Email, it waits and resumes automatically.

Nothing is uploaded. The server is bound to `127.0.0.1`, accepts only its own browser origin, and saves the active run atomically to `ProductCorpus/Results/latest.json` plus a run-specific JSON file. Recovery tests read the local macOS clipboard through the same server.

## Formatting layers

`formatting-fixtures.json` tests the text layer independently from speech recognition. Each fixture records the recogniser-style input, the exact deterministic result, facts that must survive, and transformations that must not happen. Selected fixtures also define a context-sensitive result for the optional local writing model.

Run the deterministic benchmark with:

```sh
swift run dictation-formatting-bench --fixtures ProductCorpus/formatting-fixtures.json
```

The deterministic layer handles explicit grammar such as spoken versions, decimals, percentages, paths and flags. Identifier casing, date style, unit abbreviations and similar context-dependent choices stay literal until a personal rule or guarded local-model pass has enough context to change them.
