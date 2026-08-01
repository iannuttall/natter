# Formatting parity

Tested on Ian's M3 Max with the pinned Qwen 3.5 9B MLX 4-bit model. The benchmark starts from recogniser-style text so speech recognition and text formatting failures remain distinguishable.

## Deterministic layer

The 32-case corpus covers versions, identifiers, command flags, numbers, units, dates, addresses, paths and ambiguous prose.

- Exact outputs: 32/32
- Protected facts: 100%
- Forbidden transformations avoided: 100%

Explicit technical grammar is safe to apply without a model. Current examples include `V two` to `v2`, `version two point one` to `version 2.1`, spoken decimals, percentages, paths and explicit double-hyphen flags. Prose context and homophones such as `version too` remain unchanged.

## Guarded local-model pass

Seven cases exercise choices that require context: identifier casing, Swift annotations, unit style and British date formatting.

| Prompt | Required facts | Forbidden avoided | Reference edit | p50 | p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Generic formatting | 81.8% | 100% | 12.2% | 0.50s | 0.56s |
| Minimal edit | 90.9% | 90.9% | 4.1% | 0.56s | 0.60s |
| Minimal edit + supplied vocabulary + deterministic envelope cleanup | 100% | 100% | 0% | 0.57s | 0.59s |

The generic prompt changed `Set scroll restoration: true in the router options.` into `router.options.scrollRestoration = true;`. The minimal-edit prompt prevented that rewrite but correctly declined to guess the identifier. Supplying the project vocabulary mapping produced `Set scrollRestoration: true in the router options.` without changing the surrounding instruction.

## Product boundary

- Raw stays model-free and conservative.
- Agent applies explicit technical grammar while streaming.
- Context-dependent Agent cleanup should be an optional after-stop pass with minimal-edit instructions, personal/project vocabulary and fact guards.
- Clean needs a separate cleanup benchmark because removing false starts is broader than formatting.
- Email and Article keep their existing writing prompts because restructuring is intentional in those modes.

The current seven smart cases prove the architecture and latency, not broad release readiness. Expand them with real recogniser errors and more professions before enabling smart Agent formatting by default.
