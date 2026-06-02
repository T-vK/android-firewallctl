#!/usr/bin/env bash
# Static analysis of every shell script in the repo via shellcheck.
# Skipped (PASS) when shellcheck is not installed; CI installs it.

set -u

: "${PROJECT_DIR:=$(cd "$(dirname "$0")/.." && pwd)}"

if ! command -v shellcheck >/dev/null 2>&1; then
    printf '   shellcheck not installed; skipping\n'
    exit 0
fi

# Scripts to check. The on-device wrappers use the Android /system/bin/sh
# shebang which shellcheck handles fine in -s sh mode.
targets=(
    "$PROJECT_DIR/scripts/firewallctl"
    "$PROJECT_DIR/scripts/make-deb.sh"
    "$PROJECT_DIR/magisk/customize.sh"
    "$PROJECT_DIR/magisk/service.sh"
    "$PROJECT_DIR/magisk/uninstall.sh"
    "$PROJECT_DIR/magisk/system/bin/firewall-watcher"
    "$PROJECT_DIR/tests/run-tests.sh"
    "$PROJECT_DIR/tests/test-watcher.sh"
    "$PROJECT_DIR/tests/test-packaging.sh"
    "$PROJECT_DIR/tests/test-shellcheck.sh"
)

fail=0
for t in "${targets[@]}"; do
    [ -f "$t" ] || continue
    # SC1091: don't follow non-constant sources (not relevant here).
    # SC2317: unreachable code after `case` fallthrough (false positives).
    if ! shellcheck -x -e SC1091,SC2317 "$t"; then
        printf '   - shellcheck failed: %s\n' "$t" >&2
        fail=1
    fi
done

exit "$fail"
