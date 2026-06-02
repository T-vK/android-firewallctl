#!/system/bin/sh
# Magisk late_start service - launches the firewall watcher after boot.
# Runs as root with full SELinux context (u:r:magisk:s0).

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done

sleep 15

STATE_DIR=/data/adb/firewall_default_deny
PIDFILE="$STATE_DIR/watcher.pid"
mkdir -p "$STATE_DIR"

# Grant notification permission (API 33+) once the system app is installed.
if pm path app.firewall.notify >/dev/null 2>&1; then
    pm grant app.firewall.notify android.permission.POST_NOTIFICATIONS 2>/dev/null || true
fi

if [ -f "$PIDFILE" ]; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
        exit 0
    fi
    kill "$oldpid" 2>/dev/null || true
fi

nohup /system/bin/firewall-watcher >/dev/null 2>&1 &
echo $! > "$PIDFILE"
