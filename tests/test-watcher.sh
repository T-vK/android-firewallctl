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
PACKAGES_LIST="$TMP/packages.list"
NOTIFY_APK="$TMP/FirewallNotify.apk"
mkdir -p "$STATE" "$STUBS"
touch "$NOTIFY_APK"

# packages.list: "pkgname uid flags..."
write_packages_list() {
    : >"$PACKAGES_LIST"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        pkg=${line%% *}
        uid=${line#* }
        printf '%s %s 0\n' "$pkg" "$uid" >>"$PACKAGES_LIST"
    done
}

cat > "$STUBS/pm" <<EOF
#!/usr/bin/env bash
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
export FIREWALL_PACKAGES_LIST="$PACKAGES_LIST"
export FIREWALLCTL="$STUBS/firewallctl"
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
write_packages_list <<EOF
com.example.existing.a 10001
com.example.existing.b 10002
EOF
rm -f "$STATE"/* "$TMP/firewallctl.log" "$TMP/cmd.log" "$TMP/notify.log"
run_watcher --reconcile
assert "T1: snapshot created" "[ -f '$STATE/known.txt' ]"
assert "T1: snapshot has 2 uid records" "[ \$(wc -l < '$STATE/known.txt') -eq 2 ]"
assert "T1: snapshot stores uid" "grep -qF 'com.example.existing.a 10001' '$STATE/known.txt'"
assert "T1: firewallctl NOT invoked on first run" "[ ! -f '$TMP/firewallctl.log' ]"

# ---- T2: new package is blocked and notified immediately ----
cat > "$PM_LIST" <<EOF
package:com.example.existing.a
package:com.example.existing.b
package:com.example.new.app
EOF
write_packages_list <<EOF
com.example.existing.a 10001
com.example.existing.b 10002
com.example.new.app 10003
EOF
export FIREWALL_NOTIFY_CMD="$STUBS/firewall-notify"
cat > "$STUBS/firewall-notify" <<EOF
#!/usr/bin/env bash
echo "notify-blocked \$@" >> "$TMP/notify.log"
EOF
chmod +x "$STUBS/firewall-notify"
run_watcher --reconcile
assert "T2: firewallctl was invoked" "[ -f '$TMP/firewallctl.log' ]"
assert "T2: firewallctl set +REJECT_ALL on new pkg" \
    "grep -qF 'set com.example.new.app +REJECT_ALL' '$TMP/firewallctl.log'"
assert "T2: notification requested" \
    "grep -qF 'notify-blocked com.example.new.app' '$TMP/notify.log'"
assert "T2: snapshot has uid record for new app" \
    "grep -qF 'com.example.new.app 10003' '$STATE/known.txt'"

# ---- T3: allowlisted package is skipped ----
echo "com.example.exempt" > "$STATE/allowlist.txt"
cat >> "$PM_LIST" <<EOF
package:com.example.exempt
EOF
write_packages_list <<EOF
com.example.existing.a 10001
com.example.existing.b 10002
com.example.new.app 10003
com.example.exempt 10004
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
write_packages_list <<EOF
com.example.existing.a 10001
com.example.existing.b 10002
com.example.new.app 10003
com.example.exempt 10004
com.example.another 10005
EOF
run_watcher "c" "/data/system" "unrelated.xml"
assert "T4: non-packages.xml event ignored" \
    "[ ! -f '$TMP/firewallctl.log' ]"
run_watcher "c" "/data/system" "packages.xml"
assert "T4: packages.xml event triggered reconcile" \
    "grep -qF 'set com.example.another +REJECT_ALL' '$TMP/firewallctl.log'"

# ---- T5: stale lock blocks reconcile ----
mkdir -p "$STATE/reconcile.lock"
rm -f "$TMP/firewallctl.log"
run_watcher --reconcile
assert "T5: stale lock blocks reconcile (expected)" \
    "[ ! -f '$TMP/firewallctl.log' ]"
rmdir "$STATE/reconcile.lock"

# ---- T6: reinstall with new UID is blocked again ----
unset FIREWALL_NOTIFY_CMD
export FIREWALL_NOTIFY_CMD="$STUBS/firewall-notify"
rm -f "$TMP/notify.log" "$TMP/firewallctl.log"
cat > "$PM_LIST" <<EOF
package:com.example.existing.a
package:com.example.reinstall.me
EOF
write_packages_list <<EOF
com.example.existing.a 10001
com.example.reinstall.me 20010
EOF
printf 'com.example.existing.a 10001\ncom.example.reinstall.me 10010\n' > "$STATE/known.txt"
run_watcher --reconcile
assert "T6: reinstall detected via uid change" \
    "grep -qF 'set com.example.reinstall.me +REJECT_ALL' '$TMP/firewallctl.log'"
assert "T6: reinstall notification" \
    "grep -qF 'notify-blocked com.example.reinstall.me' '$TMP/notify.log'"
assert "T6: snapshot updated to new uid" \
    "grep -qF 'com.example.reinstall.me 20010' '$STATE/known.txt'"

# ---- T7: uninstall prunes snapshot; reinstall blocks ----
rm -f "$TMP/firewallctl.log" "$TMP/notify.log"
cat > "$PM_LIST" <<EOF
package:com.example.existing.a
EOF
write_packages_list <<EOF
com.example.existing.a 10001
EOF
printf 'com.example.existing.a 10001\ncom.example.reinstall.me 20010\n' > "$STATE/known.txt"
run_watcher --reconcile
assert "T7a: uninstalled pkg pruned from snapshot" \
    "! grep -qF 'com.example.reinstall.me' '$STATE/known.txt'"
cat >> "$PM_LIST" <<EOF
package:com.example.reinstall.me
EOF
write_packages_list <<EOF
com.example.existing.a 10001
com.example.reinstall.me 30020
EOF
rm -f "$TMP/firewallctl.log" "$TMP/notify.log"
run_watcher --reconcile
assert "T7b: fresh install after uninstall blocked" \
    "grep -qF 'set com.example.reinstall.me +REJECT_ALL' '$TMP/firewallctl.log'"

exit "$fail"
