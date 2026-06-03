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
# Manual sideload exemptions only (edit by hand). The module never writes here.
# One package name per line; POLICY_REJECT_ALL is not auto-applied to these apps.
EOF
chmod 0644 "$STATE_DIR/allowlist.txt"

ui_print "- State directory: $STATE_DIR"
ui_print "- Baseline in RAM only; allowlist.txt = manual sideload exemptions"
ui_print "- Edit $STATE_DIR/allowlist.txt to exempt sideloaded packages"
ui_print "- Reboot to start the watcher"
