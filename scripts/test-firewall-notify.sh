#!/system/bin/sh
# Test block notifications without reinstalling the Magisk module or rebooting.
#
# Usage (on device, as root):
#   adb shell su -c '/system/bin/firewall-watcher --test-notify com.example.app'
#
# Or push this script:
#   adb push scripts/test-firewall-notify.sh /data/local/tmp/
#   adb shell su -c 'sh /data/local/tmp/test-firewall-notify.sh com.example.app'
#
# Checks APK presence, PackageManager visibility, then runs the same notify
# pipeline as install-detect. Read:
#   /data/adb/firewall_default_deny/watcher.log

set -u

PKG="${1:-}"
if [ -z "$PKG" ]; then
    echo "usage: $0 <package-name>" >&2
    echo "example: $0 com.android.chrome" >&2
    exit 2
fi

STATE_DIR="${FIREWALL_STATE_DIR:-/data/adb/firewall_default_deny}"
LOGFILE="$STATE_DIR/watcher.log"
WATCHER="${FIREWALL_WATCHER:-/system/bin/firewall-watcher}"

log() {
    printf '[%s] test-notify: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

log "package=$PKG"
log "logfile=$LOGFILE"

for _apk in \
    /system/priv-app/FirewallNotify/FirewallNotify.apk \
    /data/adb/modules/firewall_default_deny/system/priv-app/FirewallNotify/FirewallNotify.apk \
    /data/adb/modules/firewall_default_deny/FirewallNotify.apk
do
    if [ -f "$_apk" ]; then
        log "apk on disk: $_apk"
    fi
done

if pm path app.firewall.notify >/dev/null 2>&1; then
    log "pm path: $(pm path app.firewall.notify 2>/dev/null | head -1)"
else
    log "WARN: pm path app.firewall.notify failed (common during installs; notify may still work)"
fi

if [ ! -x "$WATCHER" ]; then
    log "ERROR: missing $WATCHER"
    exit 127
fi

if "$WATCHER" --test-notify "$PKG"; then
    log "OK — see watcher.log for notify: path=..."
    exit 0
fi

log "FAIL — tail of watcher.log:"
tail -n 30 "$LOGFILE" 2>/dev/null
exit 1
