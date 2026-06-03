#!/system/bin/sh
# Magisk late_start service - watcher daemon + FirewallNotify user APK install.
# Runs as root (u:r:magisk:s0). Allow uses Magisk su from the user-installed app.

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

install_notify_apk() {
    _apk="${MODDIR:-/data/adb/modules/firewall_default_deny}/FirewallNotify.apk"
    if [ ! -f "$_apk" ]; then
        log "WARN: FirewallNotify.apk missing at $_apk"
        return
    fi
    cp "$_apk" /data/local/tmp/FirewallNotify-install.apk
    chmod 644 /data/local/tmp/FirewallNotify-install.apk
    if pm path app.firewall.notify >/dev/null 2>&1; then
        if pm install -r /data/local/tmp/FirewallNotify-install.apk >>"$LOGFILE" 2>&1; then
            log "FirewallNotify: updated user APK"
        else
            log "FirewallNotify: pm install -r failed"
        fi
    else
        if pm install /data/local/tmp/FirewallNotify-install.apk >>"$LOGFILE" 2>&1; then
            log "FirewallNotify: installed user APK"
        else
            log "FirewallNotify: pm install failed"
        fi
    fi
    pm grant app.firewall.notify android.permission.POST_NOTIFICATIONS 2>/dev/null || true
}

install_notify_apk

if [ -f "$PIDFILE" ]; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$oldpid" ]; then
        kill "$oldpid" 2>/dev/null || true
        sleep 1
    fi
    rm -f "$PIDFILE"
fi

nohup /system/bin/firewall-watcher >/dev/null 2>&1 &
echo $! >"$PIDFILE"
log "watcher started pid=$(cat "$PIDFILE" 2>/dev/null)"
