#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
products_dir="$repo_dir/.xcode-build/Build/Products/Release"

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
    --fixtures ../dictation-bench/WritingCorpus/fixtures.json \
    --output Results/qwen-direct-mlx.json

"$products_dir/dictation-parity" \
    --fixtures ../dictation-bench/WritingCorpus/context-stress.json \
    --repeat-transcript 40 \
    --output Results/qwen-direct-mlx-context-40x.json
