#!/system/bin/sh
# Diagnose why block notifications may not appear (run as root on device).
# Usage: adb shell su -c 'sh /data/local/tmp/diagnose-firewall-notify.sh'

set -u

echo "=== FirewallNotify diagnosis ==="
echo "build: $(grep 'memdiff-v' /data/adb/firewall_default_deny/watcher.log 2>/dev/null | tail -1)"

echo ""
echo "=== APK on disk ==="
for f in \
    /system/priv-app/FirewallNotify/FirewallNotify.apk \
    /data/adb/modules/firewall_default_deny/system/priv-app/FirewallNotify/FirewallNotify.apk
do
    [ -f "$f" ] && echo "  OK $f" || echo "  -- missing $f"
done

echo ""
echo "=== Enable notifications (best-effort) ===
if [ -x /system/bin/cmd ]; then
    cmd notification unsuspend_package app.firewall.notify 2>&1 || true
    cmd appops set app.firewall.notify POST_NOTIFICATION allow 2>&1 || true
    cmd notification set_notifications_enabled_for_package app.firewall.notify true 2>&1 || true
fi

=== PackageManager ==="
pm path app.firewall.notify 2>&1 || echo "  pm path failed"
pm list packages -U app.firewall.notify 2>&1 || true
dumpsys package app.firewall.notify 2>/dev/null | grep -E 'userId=|versionCode|versionName' | head -5

echo ""
echo "=== Notification stats (app.firewall.notify) ==="
dumpsys notification --noredact 2>/dev/null | grep -A12 "key='app.firewall.notify'"

echo ""
echo "=== Channels for app.firewall.notify ==="
dumpsys notification --noredact 2>/dev/null | grep -E 'app.firewall.notify|firewall_default_deny' | head -20

echo ""
echo "=== Recent watcher notify lines ==="
grep notify /data/adb/firewall_default_deny/watcher.log 2>/dev/null | tail -15

echo ""
echo "=== Test post (no reboot) ==="
echo "  /system/bin/firewall-watcher --test-notify com.android.settings"
