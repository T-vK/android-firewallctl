#!/usr/bin/env bash
# Guard documentation consistency (no device required).
set -u

: "${PROJECT_DIR:=$(cd "$(dirname "$0")/.." && pwd)}"

fail=0
assert() {
    if ! eval "$2"; then
        printf '   - assert failed: %s\n' "$1" >&2
        fail=1
    fi
}

DOC_DIR="$PROJECT_DIR/docs"

# Required documentation files exist.
for f in ARCHITECTURE.md STATE.md COMPATIBILITY.md TROUBLESHOOTING.md DEVELOPMENT.md; do
    assert "docs/$f exists" "[ -f '$DOC_DIR/$f' ]"
done

# README links to docs.
readme="$PROJECT_DIR/README.md"
assert "README links to ARCHITECTURE.md" "grep -qF 'docs/ARCHITECTURE.md' '$readme'"
assert "README links to COMPATIBILITY.md" "grep -qF 'docs/COMPATIBILITY.md' '$readme'"

# README must not describe obsolete known.txt snapshot.
assert "README does not list known.txt in state tree" \
    "! grep -qE '^├── known\.txt|snapshot at.*known\.txt' '$readme'"

# User-facing docs must state in-memory baseline (not disk known.txt).
for doc in "$readme" "$DOC_DIR/ARCHITECTURE.md" "$DOC_DIR/STATE.md"; do
    base=$(basename "$doc")
    assert "$base mentions in-memory baseline" \
        "grep -qiE 'in-memory|in memory' '$doc'"
done

# COMPATIBILITY must document LineageOS 23 + Pixel 4 reference stack.
compat="$DOC_DIR/COMPATIBILITY.md"
assert "COMPATIBILITY mentions LineageOS 23" "grep -qF 'LineageOS 23' '$compat'"
assert "COMPATIBILITY mentions Pixel 4" "grep -qF 'Pixel 4' '$compat'"
assert "COMPATIBILITY does not discourage other devices" "! grep -qi 'unsupported' '$compat'"

# README must not claim broad LOS 20+ support without reference to compatibility doc.
assert "README points to compatibility doc for tested setup" \
    "grep -qF 'docs/COMPATIBILITY.md' '$readme'"

# Magisk quick start must not claim cmd-only notifications as primary path.
assert "README does not claim notifications are cmd-only only" \
    "! grep -q 'shell-level notification via .cmd notification' '$readme'"

# STATE.md documents allowlist path.
assert "STATE documents allowlist.txt" "grep -qF 'allowlist.txt' '$DOC_DIR/STATE.md'"

# ARCHITECTURE must not instruct readers to use known.txt for production.
assert "ARCHITECTURE does not prescribe known.txt for production" \
    "! grep -qE 'snapshot at.*known\.txt|write.*known\.txt' '$DOC_DIR/ARCHITECTURE.md'"

exit "$fail"
