#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
cd "$repo_dir"
exec python3 ProductCorpus/server.py
