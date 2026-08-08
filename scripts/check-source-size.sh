#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
source_limit="${NATTER_SOURCE_LINE_LIMIT:-850}"
test_limit="${NATTER_TEST_LINE_LIMIT:-650}"
warning_limit="${NATTER_FILE_LINE_WARNING:-600}"
failed=0

while IFS= read -r file; do
    lines="$(wc -l < "$file" | tr -d ' ')"
    relative="${file#$repo_dir/}"
    limit="$source_limit"
    if [[ "$relative" == Tests/* ]]; then
        limit="$test_limit"
    fi

    if (( lines > limit )); then
        echo "source-size error: $relative has $lines lines (limit $limit)" >&2
        failed=1
    elif (( lines > warning_limit )); then
        echo "source-size warning: $relative has $lines lines"
    fi
done < <(find "$repo_dir/Sources" "$repo_dir/Tests" -type f -name '*.swift' | sort)

exit "$failed"
