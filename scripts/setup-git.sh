#!/usr/bin/env bash
# Use T-vK as the only commit author for this repo (not the Cursor Agent defaults).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
git config user.name 'T-vK'
git config user.email '11368523+T-vK@users.noreply.github.com'
git config core.hooksPath .githooks
chmod +x .githooks/prepare-commit-msg 2>/dev/null || true
echo "git identity: $(git config user.name) <$(git config user.email)>"
echo "hooksPath: $(git config core.hooksPath)"
