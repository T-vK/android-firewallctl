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
NOTIFY_APK="$TMP/FirewallNotify.apk"
mkdir -p "$STATE" "$STUBS"
touch "$NOTIFY_APK"

cat > "$STUBS/pm" <<EOF
#!/usr/bin/env bash
# Pretends to be Android's pm.
if [ "\$1" = "list" ] && [ "\$2" = "packages" ]; then
    if [ -n "\$3" ] && [ "\$3" != "-3" ]; then
        grep -Fx "package:\$3" "$PM_LIST" 2>/dev/null || true
    else
        cat "$PM_LIST" 2>/dev/null || true
    fi
fi
if [ "\$1" = "path" ]; then
    case "\$2" in
        app.firewall.notify) echo "package:$NOTIFY_APK" ;;
    esac
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
cat > "$STUBS/app_process" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$TMP/app_process.log"
exit 0
EOF
chmod +x "$STUBS"/pm "$STUBS"/firewallctl "$STUBS"/cmd "$STUBS"/app_process

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

# ---- T1: initial snapshot does not block existing apps ----
cat > "$PM_LIST" <<EOF
package:com.example.existing.a
package:com.example.existing.b
EOF
rm -f "$STATE"/* "$TMP/firewallctl.log" "$TMP/cmd.log" "$TMP/notify.log" "$TMP/app_process.log"
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
export FIREWALL_NOTIFY_CMD="$STUBS/firewall-notify"
cat > "$STUBS/firewall-notify" <<EOF
#!/usr/bin/env bash
echo "notify-blocked \$@" >> "$TMP/notify.log"
EOF
chmod +x "$STUBS/firewall-notify"
run_watcher --reconcile
sleep 1
assert "T2: firewallctl was invoked" "[ -f '$TMP/firewallctl.log' ]"
assert "T2: firewallctl set +REJECT_ALL on new pkg" \
    "grep -qF 'set com.example.new.app +REJECT_ALL' '$TMP/firewallctl.log'"
assert "T2: notification requested" \
    "grep -qF 'notify-blocked com.example.new.app' '$TMP/notify.log'"
assert "T2: snapshot now has 3 entries" "[ \$(wc -l < '$STATE/known.txt') -eq 3 ]"

# ---- T3: allowlisted package is skipped ----
echo "com.example.exempt" > "$STATE/allowlist.txt"
cat >> "$PM_LIST" <<EOF
package:com.example.exempt
EOF
rm -f "$TMP/firewallctl.log" "$TMP/notify.log"
run_watcher --reconcile
assert "T3: firewallctl NOT invoked for allowlisted pkg" \
    "! grep -qF 'com.example.exempt' '$TMP/firewallctl.log' 2>/dev/null"
assert "T3: allowlist event logged" \
    "grep -qF 'skip com.example.exempt (allowlisted)' '$STATE/watcher.log'"

# ---- T4: inotifyd callback only fires for packages.xml ----
rm -f "$TMP/firewallctl.log" "$TMP/notify.log"
cat >> "$PM_LIST" <<EOF
package:com.example.another
EOF
run_watcher "c" "/data/system" "unrelated.xml"
assert "T4: non-packages.xml event ignored" \
    "[ ! -f '$TMP/firewallctl.log' ]"
run_watcher "c" "/data/system" "packages.xml"
assert "T4: packages.xml event triggered reconcile" \
    "grep -qF 'set com.example.another +REJECT_ALL' '$TMP/firewallctl.log'"

# ---- T5: stale lock from prior crash blocks reconcile ----
mkdir -p "$STATE/reconcile.lock"
rm -f "$TMP/firewallctl.log"
run_watcher --reconcile
assert "T5: stale lock blocks reconcile (expected)" \
    "[ ! -f '$TMP/firewallctl.log' ]"
rmdir "$STATE/reconcile.lock"

# ---- T6: uninstall then reinstall is detected as a new install ----
unset FIREWALL_NOTIFY_CMD
export FIREWALL_NOTIFY_CMD="$STUBS/firewall-notify"
rm -f "$TMP/notify.log" "$TMP/firewallctl.log"
cat > "$PM_LIST" <<EOF
package:com.example.existing.a
EOF
printf 'com.example.existing.a\ncom.example.reinstall.me\n' > "$STATE/known.txt"
run_watcher --reconcile
assert "T6a: snapshot pruned after uninstall" \
    "[ \$(wc -l < '$STATE/known.txt') -eq 1 ]"
assert "T6a: pruned pkg not in snapshot" \
    "! grep -qxF 'com.example.reinstall.me' '$STATE/known.txt'"

cat >> "$PM_LIST" <<EOF
package:com.example.reinstall.me
EOF
rm -f "$TMP/firewallctl.log" "$TMP/notify.log"
run_watcher --reconcile
sleep 1
assert "T6b: reinstall triggered block" \
    "grep -qF 'set com.example.reinstall.me +REJECT_ALL' '$TMP/firewallctl.log'"
assert "T6c: reinstall triggered notification" \
    "grep -qF 'notify-blocked com.example.reinstall.me' '$TMP/notify.log'"

exit "$fail"
