# shellcheck shell=sh
# Magisk customize.sh for firewall_default_deny.
# Runs in Magisk's busybox at install time. We only set permissions and
# create the persistent state directory. The watcher itself is started by
# service.sh after boot.

# shellcheck disable=SC2034  # read by Magisk's installer environment
SKIPUNZIP=0

ui_print "- Firewall Default Deny installing"
ui_print "- Files will overlay into /system/bin/"

# Ensure executables are marked as such on the overlay.
set_perm_recursive "$MODPATH/system/bin" 0 0 0755 0755

# Persistent runtime state. Created here so the daemon can write to it
# even before its first run.
STATE_DIR=/data/adb/firewall_default_deny
mkdir -p "$STATE_DIR"
[ -f "$STATE_DIR/allowlist.txt" ] || cat > "$STATE_DIR/allowlist.txt" <<'EOF'
# One package name per line. Packages listed here will NOT have
# POLICY_REJECT_ALL applied automatically by firewall-watcher.
# Lines starting with '#' are comments.
EOF
chmod 0644 "$STATE_DIR/allowlist.txt"
touch "$STATE_DIR/allow_queue" /data/local/tmp/firewall_default_deny_allow 2>/dev/null || true
chmod 0666 "$STATE_DIR/allow_queue" /data/local/tmp/firewall_default_deny_allow 2>/dev/null || true

ui_print "- State directory: $STATE_DIR"
ui_print "- Edit $STATE_DIR/allowlist.txt to exempt packages"
ui_print "- Reboot to start the watcher"
