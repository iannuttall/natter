#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
products_dir="$repo_dir/.xcode-build/Build/Products/Release"
model_dir="${DICTATION_AGENT_WRITING_MODEL_DIR:-$HOME/Library/Application Support/is.ian.natter/Models/agent-writing/models/mlx-community/Qwen3.5-4B-MLX-4bit}"
results_path="${NATTER_SELF_EDIT_RESULTS:-$repo_dir/Results/agent-self-edit-eval.json}"
iterations="${NATTER_SELF_EDIT_ITERATIONS:-1}"

if [[ ! -f "$model_dir/config.json" ]]; then
    print -u2 "Agent writing model is not installed at $model_dir"
    exit 2
fi

cd "$repo_dir"

xcodebuild build \
    -quiet \
    -scheme dictation-parity \
    -destination 'platform=macOS,arch=arm64' \
    -configuration Release \
    -derivedDataPath .xcode-build \
    CODE_SIGNING_ALLOWED=NO \
    -skipPackagePluginValidation \
    -skipMacroValidation

"$products_dir/dictation-parity" \
    --fixtures ProductCorpus/agent-self-edit-fixtures.json \
    --model-directory "$model_dir" \
    --strategy agent-self-edits \
    --iterations "$iterations" \
    --output "$results_path"

node scripts/check-agent-self-edit-evals.mjs "$results_path"
