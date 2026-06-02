#!/usr/bin/env bash
# Functional tests for magisk/system/bin/firewall-watcher.
#
# Strategy: build an isolated PATH with stub `pm`, `firewallctl`, `cmd`
# binaries that read/record from files in a temp state dir, then drive the
# watcher in --reconcile mode and inspect side effects.

set -u

: "${PROJECT_DIR:=$(cd "$(dirname "$0")/.." && pwd)}"
# The watcher uses an Android shebang (#!/system/bin/sh) which doesn't
# exist on Linux. Invoke via /bin/sh so the tests are host-portable.
WATCHER="$PROJECT_DIR/magisk/system/bin/firewall-watcher"
run_watcher() { sh "$WATCHER" "$@"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STATE="$TMP/state"
STUBS="$TMP/bin"
PM_LIST="$TMP/pm-output"
mkdir -p "$STATE" "$STUBS"

# --- stubs ---
cat > "$STUBS/pm" <<EOF
#!/usr/bin/env bash
# Pretends to be Android's pm. Only honors "list packages -3".
if [ "\$1" = "list" ] && [ "\$2" = "packages" ]; then
    cat "$PM_LIST" 2>/dev/null || true
fi
EOF
cat > "$STUBS/firewallctl" <<EOF
#!/usr/bin/env bash
# Records its argv so the test can assert what was invoked.
echo "\$@" >> "$TMP/firewallctl.log"
EOF
cat > "$STUBS/cmd" <<EOF
#!/usr/bin/env bash
# Stub for \`cmd notification ...\`. Records argv.
echo "\$@" >> "$TMP/cmd.log"
EOF
chmod +x "$STUBS"/pm "$STUBS"/firewallctl "$STUBS"/cmd

export FIREWALL_STATE_DIR="$STATE"
export PATH="$STUBS:$PATH"

fail=0
assert() {
    if ! eval "$2"; then
        printf '   - assert failed: %s\n' "$1" >&2
        fail=1
    fi
}

# ---- T1: initial snapshot does not block existing apps ----
cat > "$PM_LIST" <<EOF
package:com.example.existing.a
package:com.example.existing.b
EOF
rm -f "$STATE"/* "$TMP/firewallctl.log" "$TMP/cmd.log"
run_watcher --reconcile
assert "T1: snapshot created" "[ -f '$STATE/known.txt' ]"
assert "T1: snapshot has 2 entries" "[ \$(wc -l < '$STATE/known.txt') -eq 2 ]"
assert "T1: firewallctl NOT invoked on first run" "[ ! -f '$TMP/firewallctl.log' ]"

# ---- T2: new package is blocked ----
cat > "$PM_LIST" <<EOF
package:com.example.existing.a
package:com.example.existing.b
package:com.example.new.app
EOF
run_watcher --reconcile
assert "T2: firewallctl was invoked" "[ -f '$TMP/firewallctl.log' ]"
assert "T2: firewallctl set +REJECT_ALL on new pkg" \
    "grep -qF 'set com.example.new.app +REJECT_ALL' '$TMP/firewallctl.log'"
assert "T2: notification posted" \
    "grep -q 'com.example.new.app' '$TMP/cmd.log'"
assert "T2: snapshot now has 3 entries" "[ \$(wc -l < '$STATE/known.txt') -eq 3 ]"

# ---- T3: allowlisted package is skipped ----
echo "com.example.exempt" > "$STATE/allowlist.txt"
cat >> "$PM_LIST" <<EOF
package:com.example.exempt
EOF
rm -f "$TMP/firewallctl.log" "$TMP/cmd.log"
run_watcher --reconcile
assert "T3: firewallctl NOT invoked for allowlisted pkg" \
    "! grep -qF 'com.example.exempt' '$TMP/firewallctl.log' 2>/dev/null"
assert "T3: allowlist event logged" \
    "grep -qF 'skip com.example.exempt (allowlisted)' '$STATE/watcher.log'"

# ---- T4: inotifyd callback only fires for packages.xml ----
rm -f "$TMP/firewallctl.log" "$TMP/cmd.log"
cat >> "$PM_LIST" <<EOF
package:com.example.another
EOF
run_watcher "c" "/data/system" "unrelated.xml"
assert "T4: non-packages.xml event ignored" \
    "[ ! -f '$TMP/firewallctl.log' ]"
run_watcher "c" "/data/system" "packages.xml"
assert "T4: packages.xml event triggered reconcile" \
    "grep -qF 'set com.example.another +REJECT_ALL' '$TMP/firewallctl.log'"

# ---- T5: stale lock from prior crash is cleared on reconcile no-op ----
mkdir -p "$STATE/reconcile.lock"  # simulate stale lock
rm -f "$TMP/firewallctl.log"
run_watcher --reconcile  # should bail because lock held
assert "T5: stale lock blocks reconcile (expected)" \
    "[ ! -f '$TMP/firewallctl.log' ]"
rmdir "$STATE/reconcile.lock"

exit "$fail"
