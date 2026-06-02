#!/system/bin/sh
# Magisk uninstall.sh for firewall_default_deny.
# Stops the running watcher and removes the state directory.
# Note: policies already applied to UIDs are NOT cleared here. Use
# `firewallctl clear <pkg>` (while the module is still installed) or
# the system Settings toggles to re-enable network access for a given app.

PIDFILE=/data/adb/firewall_default_deny/watcher.pid
if [ -f "$PIDFILE" ]; then
    pid="$(cat "$PIDFILE")"
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
fi

rm -rf /data/adb/firewall_default_deny
