# Product corpus

This local browser harness tests the behaviour around the chosen speech and writing models. It does not repeat the model-selection or accent benchmark.

Run it from the repository root:

```sh
./scripts/serve-product-corpus.sh
```

Open `http://127.0.0.1:4173`, launch the native Dictation app, and work through the cards. The browser records inserted text, focus events, input timing, recovery clipboard content, automatic assertions and manual observations in local storage. Export the JSON when a session is complete.

Quit Monologue before a run because it uses the same double Right Option shortcut. For each card, select the displayed mode in Dictation, click **Arm and focus field**, then start dictating with the native hotkey.

Nothing is uploaded. The only network listener is Python's static server bound to `127.0.0.1`.
