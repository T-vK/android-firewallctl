#!/usr/bin/env bash
# Functional tests for magisk/system/bin/firewall-watcher.

set -u

: "${PROJECT_DIR:=$(cd "$(dirname "$0")/.." && pwd)}"
WATCHER="$PROJECT_DIR/magisk/system/bin/firewall-watcher"
run_watcher() { sh "$WATCHER" "$@"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

STATE="$TMP/state"
STUBS="$TMP/bin"
PM_LIST="$TMP/pm-output"
mkdir -p "$STATE" "$STUBS"

cat > "$STUBS/pm" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "list" ] && [ "\$2" = "packages" ]; then
    if [ -n "\$3" ] && [ "\$3" != "-3" ]; then
        grep -Fx "package:\$3" "$PM_LIST" 2>/dev/null || true
    else
        cat "$PM_LIST" 2>/dev/null || true
    fi
fi
EOF
cat > "$STUBS/firewallctl" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$TMP/firewallctl.log"
EOF
cat > "$STUBS/cmd" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$TMP/cmd.log"
EOF
chmod +x "$STUBS"/pm "$STUBS"/firewallctl "$STUBS"/cmd

export FIREWALL_STATE_DIR="$STATE"
export FIREWALLCTL="$STUBS/firewallctl"
export FIREWALL_INSTALL_SETTLE_SEC=0
export PATH="$STUBS:$PATH"

fail=0
assert() {
    if ! eval "$2"; then
        printf '   - assert failed: %s\n' "$1" >&2
        fail=1
    fi
}

cat > "$PM_LIST" <<EOF
package:com.example.existing.a
package:com.example.existing.b
EOF
rm -f "$STATE"/* "$TMP/firewallctl.log" "$TMP/cmd.log"
run_watcher --reconcile
assert "T1: snapshot created" "[ -f '$STATE/known.txt' ]"
assert "T1: snapshot has 2 entries" "[ \$(wc -l < '$STATE/known.txt') -eq 2 ]"
assert "T1: firewallctl NOT invoked on first run" "[ ! -f '$TMP/firewallctl.log' ]"

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
cat >> "$PM_LIST" <<EOF
package:com.example.from.list
EOF
rm -f "$TMP/firewallctl.log"
run_watcher "w" "/data/system" "packages.list"
assert "T4b: packages.list event triggered reconcile" \
    "grep -qF 'set com.example.from.list +REJECT_ALL' '$TMP/firewallctl.log'"

mkdir -p "$STATE/reconcile.lock"
rm -f "$TMP/firewallctl.log"
run_watcher --reconcile
assert "T5: stale lock blocks reconcile (expected)" \
    "[ ! -f '$TMP/firewallctl.log' ]"
rmdir "$STATE/reconcile.lock"

cat > "$STUBS/firewallctl" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$TMP/firewallctl.log"
case "\$*" in
    *com.example.fail*) exit 1 ;;
esac
EOF
chmod +x "$STUBS/firewallctl"
cat > "$PM_LIST" <<EOF
package:com.example.ok
package:com.example.fail
EOF
printf 'com.example.ok\n' > "$STATE/known.txt"
rm -f "$TMP/firewallctl.log"
run_watcher --reconcile
assert "T6: snapshot not updated when apply fails" \
    "grep -qxF 'com.example.ok' '$STATE/known.txt'"
assert "T6: failed pkg not added to snapshot" \
    "! grep -qF 'com.example.fail' '$STATE/known.txt'"

exit "$fail"
