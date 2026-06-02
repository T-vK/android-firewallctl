#!/usr/bin/env bash
# Top-level test dispatcher. Runs every tests/test-*.sh script and tallies
# pass/fail. Designed to be invoked from `make test` and from CI.
#
# Exit code: 0 if every test script returns 0, 1 otherwise.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export PROJECT_DIR

pass=0
fail=0
failed_tests=()

printf '== firewallctl tests ==\n'
printf '   project: %s\n\n' "$PROJECT_DIR"

for t in "$SCRIPT_DIR"/test-*.sh; do
    [ -f "$t" ] || continue
    name="$(basename "$t")"
    printf '>> %s\n' "$name"
    if "$t"; then
        pass=$((pass + 1))
        printf '   PASS\n\n'
    else
        fail=$((fail + 1))
        failed_tests+=("$name")
        printf '   FAIL\n\n'
    fi
done

printf -- '----\n'
printf 'passed: %d\n' "$pass"
printf 'failed: %d\n' "$fail"
if [ "$fail" -ne 0 ]; then
    printf 'failures:\n'
    for f in "${failed_tests[@]}"; do
        printf '  - %s\n' "$f"
    done
    exit 1
fi
exit 0
