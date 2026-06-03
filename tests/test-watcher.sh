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
echo "$@" >> "${FIREWALL_TEST_CMD_LOG:-/dev/null}"
EOF
cat > "$STUBS/am" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "${FIREWALL_TEST_AM_LOG:-/dev/null}"
EOF
chmod +x "$STUBS"/pm "$STUBS"/firewallctl "$STUBS"/cmd "$STUBS"/am

export FIREWALL_STATE_DIR="$STATE"
export FIREWALL_PACKAGES_LIST="$PKG_LIST"
export FIREWALL_TEST_PM_LIST="$PM_LIST"
export FIREWALL_TEST_CMD_LOG="$TMP/cmd.log"
export FIREWALL_TEST_AM_LOG="$TMP/am.log"
export PATH="$STUBS:$PATH"
export FIREWALLCTL="$STUBS/firewallctl"

fail=0
assert() {
    if ! eval "$2"; then
        printf '   - assert failed: %s\n' "$1" >&2
        fail=1
    fi
}

reset_state() {
    rm -f "$STATE"/* "$STATE/.snapshot_initialized" "$TMP/firewallctl.log" "$TMP/cmd.log" "$TMP/am.log" 2>/dev/null
    : >"$PKG_LIST"
}

write_pm() {
    cat > "$PM_LIST"
}

write_uids() {
    cat > "$PKG_LIST"
}

# ---- T1: bootstrap records apps with uid, does not block ----
reset_state
write_pm <<EOF
package:com.example.existing.a
package:com.example.existing.b
EOF
write_uids <<EOF
com.example.existing.a 10101
com.example.existing.b 10102
EOF
run_watcher --reconcile
assert "T1: init flag created" "[ -f '$STATE/.snapshot_initialized' ]"
assert "T1: snapshot created" "[ -f '$STATE/known.txt' ]"
assert "T1: snapshot has 2 entries" "[ \$(wc -l < '$STATE/known.txt') -eq 2 ]"
assert "T1: firewallctl NOT invoked on bootstrap" "[ ! -f '$TMP/firewallctl.log' ]"

# ---- T2: new package is blocked ----
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
run_watcher --reconcile
assert "T2: firewallctl set on new pkg" \
    "grep -qF 'set com.example.new.app +REJECT_ALL' '$TMP/firewallctl.log'"
assert "T2: snapshot has 3 entries" "[ \$(wc -l < '$STATE/known.txt') -eq 3 ]"

# ---- T3: allowlisted package is skipped ----
echo "com.example.exempt" > "$STATE/allowlist.txt"
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
run_watcher --reconcile
assert "T3: exempt not blocked" \
    "! grep -qF 'com.example.exempt' '$TMP/firewallctl.log' 2>/dev/null"

# ---- T4: packages.list event triggers reconcile ----
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
run_watcher packages.list
assert "T4: another blocked via packages.list event" \
    "grep -qF 'set com.example.another +REJECT_ALL' '$TMP/firewallctl.log'"

# ---- T5: name-only bootstrap entry blocks when uid appears ----
reset_state
write_pm <<EOF
package:com.race.installing
package:com.example.existing.a
EOF
write_uids <<EOF
com.example.existing.a 10101
EOF
run_watcher --reconcile
assert "T5: race pkg recorded name-only in snapshot" \
    "grep -qxF 'com.race.installing' '$STATE/known.txt'"
write_uids <<EOF
com.example.existing.a 10101
com.race.installing 10200
EOF
rm -f "$TMP/firewallctl.log"
run_watcher --reconcile
assert "T5: race pkg blocked once uid exists" \
    "grep -qF 'set com.race.installing +REJECT_ALL' '$TMP/firewallctl.log'"

# ---- T6: reinstall (recent uninstall + new uid) ----
reset_state
write_pm <<EOF
package:com.reinstall.app
EOF
write_uids <<EOF
com.reinstall.app 10301
EOF
run_watcher --reconcile
echo "com.reinstall.app 10301" > "$STATE/known.txt"
echo "com.reinstall.app" >> "$STATE/recent_uninstalled"
write_uids <<EOF
com.reinstall.app 10399
EOF
rm -f "$TMP/firewallctl.log"
run_watcher --reconcile
assert "T6: reinstall blocked after uid change" \
    "grep -qF 'set com.reinstall.app +REJECT_ALL' '$TMP/firewallctl.log'"

# ---- T7: in-snapshot same uid is not re-blocked ----
reset_state
write_pm <<EOF
package:com.stable.app
EOF
write_uids <<EOF
com.stable.app 10401
EOF
run_watcher --reconcile
rm -f "$TMP/firewallctl.log"
run_watcher --reconcile
assert "T7: stable app not blocked twice" \
    "[ ! -f '$TMP/firewallctl.log' ]"

# ---- T8: allowlist ignored on reinstall ----
reset_state
write_pm <<EOF
package:com.reinstall.allow
EOF
write_uids <<EOF
com.reinstall.allow 10501
EOF
run_watcher --reconcile
echo "com.reinstall.allow" > "$STATE/allowlist.txt"
echo "com.reinstall.allow 10501" > "$STATE/known.txt"
echo "com.reinstall.allow" >> "$STATE/recent_uninstalled"
write_uids <<EOF
com.reinstall.allow 10599
EOF
rm -f "$TMP/firewallctl.log"
run_watcher --reconcile
assert "T8: allowlist ignored on reinstall" \
    "grep -qF 'set com.reinstall.allow +REJECT_ALL' '$TMP/firewallctl.log'"

# ---- T9: allowlist.txt does not exempt reinstall ----
reset_state
write_pm <<EOF
package:com.reinstall.allowlisted
EOF
write_uids <<EOF
com.reinstall.allowlisted 10701
EOF
run_watcher --reconcile
echo "com.reinstall.allowlisted" > "$STATE/allowlist.txt"
echo "com.reinstall.allowlisted 10701" > "$STATE/known.txt"
echo "com.reinstall.allowlisted" >> "$STATE/recent_uninstalled"
write_uids <<EOF
com.reinstall.allowlisted 10799
EOF
rm -f "$TMP/firewallctl.log"
run_watcher --reconcile
assert "T9: allowlist.txt does not exempt reinstall" \
    "grep -qF 'set com.reinstall.allowlisted +REJECT_ALL' '$TMP/firewallctl.log'"
assert "T9: not skip allowlisted on reinstall" \
    "! grep -qF 'skip com.reinstall.allowlisted (allowlisted)' '$STATE/watcher.log'"

exit "$fail"
