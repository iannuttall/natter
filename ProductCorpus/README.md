# Product corpus

This local browser harness tests the behaviour around the chosen speech and writing models. It does not repeat the model-selection or accent benchmark.

Run it from the repository root:

```sh
./scripts/serve-product-corpus.sh
```

Open `http://127.0.0.1:4173`, launch the native Dictation app, and press **Start run** once. The runner selects each mode through a local app URL, focuses the field, recognises the Right Option or Right Control start/stop sequence, captures input timing, grades the settled result and advances automatically.

Quit Monologue before a run because it uses the same double Right Option shortcut. After starting, only use the native hotkey and read the displayed script exactly. There are no checkboxes, notes or export step.

Email and Article scenarios are saved as skipped when their optional Writing tools model is not installed, so the rest of the run can continue without waiting.

Nothing is uploaded. The server is bound to `127.0.0.1`, accepts only its own browser origin, and saves the active run atomically to `ProductCorpus/Results/latest.json` plus a run-specific JSON file. Recovery tests read the local macOS clipboard through the same server.
