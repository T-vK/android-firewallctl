#!/system/bin/sh
# Magisk late_start service - launches the firewall watcher after boot.
# Runs as root with full SELinux context (u:r:magisk:s0).

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done

sleep 15

STATE_DIR=/data/adb/firewall_default_deny
PIDFILE="$STATE_DIR/watcher.pid"
LOGFILE="$STATE_DIR/watcher.log"
mkdir -p "$STATE_DIR"

log() {
    printf '[%s] service: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOGFILE"
}

for bin in /system/bin/firewall-watcher /system/bin/firewallctl /system/bin/firewallctl.dex.jar; do
    if [ ! -f "$bin" ]; then
        log "ERROR: missing $bin (module overlay not active?)"
        exit 0
    fi
done

touch "$STATE_DIR/allow_queue" /data/local/tmp/firewall_default_deny_allow 2>/dev/null || true
chmod 0666 "$STATE_DIR/allow_queue" /data/local/tmp/firewall_default_deny_allow 2>/dev/null || true
rm -f /data/local/tmp/firewall_default_deny_allow.fifo 2>/dev/null || true
mkfifo /data/local/tmp/firewall_default_deny_allow.fifo 2>/dev/null || true
chmod 0666 /data/local/tmp/firewall_default_deny_allow.fifo 2>/dev/null || true

if pm path app.firewall.notify >/dev/null 2>&1; then
    pm grant app.firewall.notify android.permission.POST_NOTIFICATIONS 2>/dev/null || true
else
    log "WARN: app.firewall.notify not installed"
fi

if [ -f "$PIDFILE" ]; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$oldpid" ]; then
        kill "$oldpid" 2>/dev/null || true
        sleep 1
    fi
    rm -f "$PIDFILE"
fi

nohup /system/bin/firewall-watcher >/dev/null 2>&1 &
echo $! > "$PIDFILE"
log "watcher started pid=$(cat "$PIDFILE" 2>/dev/null)"
