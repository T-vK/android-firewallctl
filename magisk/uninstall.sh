#!/system/bin/sh
# Magisk uninstall.sh for firewall_default_deny.

PIDFILE=/data/adb/firewall_default_deny/watcher.pid
if [ -f "$PIDFILE" ]; then
    pid="$(cat "$PIDFILE")"
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
fi

pm uninstall app.firewall.notify 2>/dev/null || true

rm -rf /data/adb/firewall_default_deny
