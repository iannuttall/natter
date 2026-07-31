#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
cd "$repo_dir"
python3 -m http.server 4173 --bind 127.0.0.1 --directory ProductCorpus
