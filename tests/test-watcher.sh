#!/usr/bin/env bash
# Functional tests for firewall-watcher (in-memory baseline + wake fifo daemon).
set -u

: "${PROJECT_DIR:=$(cd "$(dirname "$0")/.." && pwd)}"
WATCHER="$PROJECT_DIR/magisk/system/bin/firewall-watcher"

TMP="$(mktemp -d)"
trap 'kill "$(cat "$TMP/daemon.pid" 2>/dev/null)" 2>/dev/null; rm -rf "$TMP"' EXIT

STATE="$TMP/state"
STUBS="$TMP/bin"
PM_LIST="$TMP/pm-output"
PKG_LIST="$TMP/packages.list"
mkdir -p "$STATE" "$STUBS"

cat > "$STUBS/pm" <<'PMEOF'
#!/usr/bin/env bash
if [ "$1" = "list" ] && [ "$2" = "packages" ]; then
    if [ "$3" = "-U" ] && [ -n "${4:-}" ]; then
        _pkg="$4"
        _uid=$(awk -v p="$_pkg" '$1 == p { print $2; exit }' "$FIREWALL_PACKAGES_LIST" 2>/dev/null)
        [ -n "$_uid" ] && echo "package:$_pkg uid:$_uid"
        exit 0
    fi
    cat "${FIREWALL_TEST_PM_LIST:?}" 2>/dev/null
fi
PMEOF
cat > "$STUBS/firewallctl" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$TMP/firewallctl.log"
case "\$1" in
    set) exit 0 ;;
    get) echo "POLICY_REJECT_ALL" ;;
    *) exit 0 ;;
esac
EOF
cat > "$STUBS/cmd" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${FIREWALL_TEST_AM_LOG:-/dev/null}"
EOF
cat > "$STUBS/am" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${FIREWALL_TEST_AM_LOG:-/dev/null}"
EOF

cat > "$STUBS/app_process" <<'EOF'
#!/usr/bin/env bash
echo "app_process $*" >> "${FIREWALL_TEST_AM_LOG:-/dev/null}"
exit 0
EOF
chmod +x "$STUBS"/pm "$STUBS"/firewallctl "$STUBS"/cmd "$STUBS"/am "$STUBS"/app_process

export FIREWALL_STATE_DIR="$STATE"
export FIREWALL_PACKAGES_LIST="$PKG_LIST"
export FIREWALL_TEST_PM_LIST="$PM_LIST"
export FIREWALL_TEST_AM_LOG="$TMP/am.log"
export PATH="$STUBS:$PATH"
export FIREWALLCTL="$STUBS/firewallctl"
export FIREWALL_MIN_USER_PACKAGES=2
export FIREWALL_WATCHER_SAFETY_INTERVAL=3600

fail=0
assert() {
    if ! eval "$2"; then
        printf '   - assert failed: %s\n' "$1" >&2
        fail=1
    fi
}

reset_state() {
    kill "$(cat "$TMP/daemon.pid" 2>/dev/null)" 2>/dev/null || true
    rm -f "$TMP/daemon.pid"
    sleep 0.2
    rm -f "$STATE"/* "$TMP/firewallctl.log" "$TMP/am.log" 2>/dev/null
    : >"$PKG_LIST"
}

write_pm() {
    cat >"$PM_LIST"
}

write_uids() {
    cat >"$PKG_LIST"
}

start_daemon() {
    sh "$WATCHER" >>"$STATE/watcher.log" 2>&1 &
    echo $! >"$TMP/daemon.pid"
    sleep 1
}

wake_watcher() {
  if [ -p "$STATE/package_events.fifo" ]; then
    printf '\n' >>"$STATE/package_events.fifo"
  else
    sh "$WATCHER" --wake
  fi
  sleep 0.6
}

# ---- T1: baseline on start does not block ----
reset_state
write_pm <<EOF
package:com.example.existing.a
package:com.example.existing.b
EOF
write_uids <<EOF
com.example.existing.a 10101
com.example.existing.b 10102
EOF
start_daemon
assert "T1: no known.txt on disk" "[ ! -f '$STATE/known.txt' ]"
assert "T1: firewallctl NOT invoked on baseline load" "[ ! -f '$TMP/firewallctl.log' ]"

# ---- T2: new package blocked after wake ----
write_pm <<EOF
package:com.example.existing.a
package:com.example.existing.b
package:com.example.new.app
EOF
write_uids <<EOF
com.example.existing.a 10101
com.example.existing.b 10102
com.example.new.app 10103
EOF
wake_watcher
assert "T2: firewallctl set on new pkg" \
    "grep -qF 'set com.example.new.app +REJECT_ALL' '$TMP/firewallctl.log'"
assert "T2: notification delivered" \
    "grep -qE 'notify: (path=|posted for) com.example.new.app' '$STATE/watcher.log' || grep -q 'com.example.new.app' '$TMP/am.log'"

# ---- T3: manual allowlist skip ----
echo "com.example.exempt" >"$STATE/allowlist.txt"
write_pm <<EOF
package:com.example.existing.a
package:com.example.existing.b
package:com.example.new.app
package:com.example.exempt
EOF
write_uids <<EOF
com.example.existing.a 10101
com.example.existing.b 10102
com.example.new.app 10103
com.example.exempt 10104
EOF
rm -f "$TMP/firewallctl.log"
wake_watcher
assert "T3: exempt not blocked" \
    "! grep -qF 'com.example.exempt' '$TMP/firewallctl.log' 2>/dev/null"
assert "T3: skip logged" \
    "grep -qF 'skip com.example.exempt (allowlisted)' '$STATE/watcher.log'"

# ---- T4: packages.list wake ----
write_pm <<EOF
package:com.example.existing.a
package:com.example.existing.b
package:com.example.new.app
package:com.example.exempt
package:com.example.another
EOF
write_uids <<EOF
com.example.existing.a 10101
com.example.existing.b 10102
com.example.new.app 10103
com.example.exempt 10104
com.example.another 10105
EOF
rm -f "$TMP/firewallctl.log"
sh "$WATCHER" --wake packages.list
sleep 0.6
assert "T4: another blocked" \
    "grep -qF 'set com.example.another +REJECT_ALL' '$TMP/firewallctl.log'"

# ---- T5: uid appears for tracked name (reinstall-style) ----
reset_state
write_pm <<EOF
package:com.race.installing
package:com.example.existing.a
EOF
write_uids <<EOF
com.example.existing.a 10101
EOF
start_daemon
write_uids <<EOF
com.example.existing.a 10101
com.race.installing 10200
EOF
wake_watcher
assert "T5: race pkg blocked when uid appears" \
    "grep -qF 'set com.race.installing +REJECT_ALL' '$TMP/firewallctl.log'"

# ---- T6: reinstall uid change ----
reset_state
write_pm <<EOF
package:com.reinstall.app
package:com.helper.app
EOF
write_uids <<EOF
com.reinstall.app 10301
com.helper.app 10302
EOF
start_daemon
write_uids <<EOF
com.reinstall.app 10399
com.helper.app 10302
EOF
rm -f "$TMP/firewallctl.log"
wake_watcher
assert "T6: reinstall blocked" \
    "grep -qF 'set com.reinstall.app +REJECT_ALL' '$TMP/firewallctl.log'"

# ---- T7: stable app not re-blocked ----
reset_state
write_pm <<EOF
package:com.stable.app
package:com.helper.app
EOF
write_uids <<EOF
com.stable.app 10401
com.helper.app 10402
EOF
start_daemon
rm -f "$TMP/firewallctl.log"
wake_watcher
assert "T7: no spurious block" "[ ! -f '$TMP/firewallctl.log' ]"

# ---- T8: allowlist ignored on reinstall (uid change) ----
reset_state
write_pm <<EOF
package:com.reinstall.allow
package:com.helper.app
EOF
write_uids <<EOF
com.reinstall.allow 10501
com.helper.app 10502
EOF
start_daemon
echo "com.reinstall.allow" >"$STATE/allowlist.txt"
write_uids <<EOF
com.reinstall.allow 10599
com.helper.app 10502
EOF
rm -f "$TMP/firewallctl.log"
wake_watcher
assert "T8: allowlist ignored on reinstall" \
    "grep -qF 'set com.reinstall.allow +REJECT_ALL' '$TMP/firewallctl.log'"

# ---- T10: empty list does not establish baseline ----
reset_state
write_pm <<EOF
EOF
write_uids <<EOF
EOF
start_daemon
assert "T10: no block on empty" "[ ! -f '$TMP/firewallctl.log' ]"

# ---- T11: suspicious drop ignored ----
reset_state
write_pm <<EOF
package:com.example.existing.a
package:com.example.existing.b
package:com.example.existing.c
EOF
write_uids <<EOF
com.example.existing.a 10101
com.example.existing.b 10102
com.example.existing.c 10103
EOF
start_daemon
write_pm <<EOF
package:com.example.existing.a
EOF
write_uids <<EOF
com.example.existing.a 10101
EOF
rm -f "$TMP/firewallctl.log"
wake_watcher
assert "T11: suspicious drop no block" "[ ! -f '$TMP/firewallctl.log' ]"

# ---- T12: inotifyd must not treat --wake as a watch path ----
assert "T12: inotifyd invocation has no --wake watch path" \
    "! grep -q 'inotifyd \"\$0\" --wake' \"\$WATCHER\""


exit "$fail"
