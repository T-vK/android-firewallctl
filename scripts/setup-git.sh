#!/usr/bin/env bash
# Use T-vK as the only commit author for this repo (not the Cursor Agent defaults).
# Removes Cursor-managed hooks that append Co-authored-by trailers.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Cursor installs per-workspace hooks under ~/.cursor/agent-hooks/<b64-path>.
_ws_hook="$(printf '%s' "$ROOT" | base64 -w 0 2>/dev/null || printf '%s' "$ROOT" | base64)"
_agent_hooks="${HOME}/.cursor/agent-hooks/${_ws_hook}"
if [ -d "$_agent_hooks" ]; then
    rm -rf "$_agent_hooks"
    echo "removed Cursor agent hooks: $_agent_hooks"
fi
rmdir "${HOME}/.cursor/agent-hooks" 2>/dev/null || true

git config user.name 'T-vK'
git config user.email '11368523+T-vK@users.noreply.github.com'
git config core.hooksPath .githooks
chmod +x .githooks/prepare-commit-msg .githooks/pre-commit 2>/dev/null || true
echo "git identity: $(git config user.name) <$(git config user.email)>"
echo "hooksPath: $(git config core.hooksPath)"
