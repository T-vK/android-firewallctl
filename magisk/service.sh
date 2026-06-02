#!/system/bin/sh
# Magisk late_start service - launches the firewall watcher after boot.
# Runs as root with full SELinux context (u:r:magisk:s0).

# Wait for the framework to be fully up.
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done

# Small grace period so package manager / netd are ready.
sleep 15

# Avoid double-launch on hot module updates.
PIDFILE=/data/adb/firewall_default_deny/watcher.pid
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    exit 0
fi

nohup /system/bin/firewall-watcher >/dev/null 2>&1 &
echo $! > "$PIDFILE"
