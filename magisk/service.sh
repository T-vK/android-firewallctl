#!/system/bin/sh
# Magisk late_start service - watcher + FirewallNotify (priv-app overlay or pm install fallback).

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done

sleep 15

STATE_DIR=/data/adb/firewall_default_deny
PIDFILE="$STATE_DIR/watcher.pid"
LOGFILE="$STATE_DIR/watcher.log"
MOD="${MODDIR:-/data/adb/modules/firewall_default_deny}"
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

find_notify_apk() {
    if [ -f "$MOD/system/priv-app/FirewallNotify/FirewallNotify.apk" ]; then
        echo "$MOD/system/priv-app/FirewallNotify/FirewallNotify.apk"
        return 0
    fi
    if [ -f "$MOD/FirewallNotify.apk" ]; then
        echo "$MOD/FirewallNotify.apk"
        return 0
    fi
    return 1
}

ensure_notify_app() {
    if pm path app.firewall.notify >/dev/null 2>&1; then
        log "FirewallNotify: $(pm path app.firewall.notify 2>/dev/null | head -1)"
        pm grant app.firewall.notify android.permission.POST_NOTIFICATIONS 2>/dev/null || true
        return 0
    fi
    log "WARN: app.firewall.notify not visible to pm (priv-app overlay missing?)"
    _apk=$(find_notify_apk) || {
        log "ERROR: FirewallNotify.apk not found under $MOD"
        return 1
    }
    cp "$_apk" /data/local/tmp/FirewallNotify-install.apk
    chmod 644 /data/local/tmp/FirewallNotify-install.apk
    if pm install -r -g -d --user 0 /data/local/tmp/FirewallNotify-install.apk >>"$LOGFILE" 2>&1; then
        log "FirewallNotify: installed via pm (fallback)"
    elif cmd package install -r -g --user 0 -t /data/local/tmp/FirewallNotify-install.apk \
            >>"$LOGFILE" 2>&1; then
        log "FirewallNotify: installed via cmd package install (fallback)"
    else
        log "ERROR: pm/cmd install FirewallNotify failed (see log above)"
        return 1
    fi
    pm grant app.firewall.notify android.permission.POST_NOTIFICATIONS 2>/dev/null || true
    return 0
}

ensure_notify_app

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
