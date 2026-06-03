#!/system/bin/sh
# Event-driven new user-app detector (no poll loop).
# Posts a visible notification via FirewallNotify (not cmd/shell channel).
#
#   adb push scripts/install-detect-inotify.sh /data/local/tmp/
#   adb shell su -c 'sh /data/local/tmp/install-detect-inotify.sh'
#
# Requires FirewallNotify (Magisk module priv-app). Rebuild/update module after
# APK changes so install_detect notifications are supported.

BASE=/data/local/tmp/.ni_base
CUR=/data/local/tmp/.ni_cur
RUNNER=/data/adb/firewall_default_deny/install-detect-inotify.sh
NOTIFY_PKG=app.firewall.notify
AM="${AM:-/system/bin/am}"
APP_PROCESS="${APP_PROCESS:-/system/bin/app_process}"
[ -x "$AM" ] || AM=am
[ -x "$APP_PROCESS" ] || APP_PROCESS=app_process

notify_apk_path() {
    _p=$(pm path "$NOTIFY_PKG" 2>/dev/null | head -1 | sed 's/^package://')
    [ -n "$_p" ] && [ -f "$_p" ] && echo "$_p"
}

notify_new_pkg() {
    _pkg="$1"
    [ -n "$_pkg" ] || return 1
    _when=$(date '+%H:%M:%S' 2>/dev/null || date)

    # FirewallNotify channel (IMPORTANCE_HIGH) — visible unlike cmd shell_cmd.
    if pm path "$NOTIFY_PKG" >/dev/null 2>&1; then
        if "$AM" start --user 0 \
                -n "${NOTIFY_PKG}/.PostNotificationActivity" \
                --es package "$_pkg" \
                --es kind install_detect \
                --es when "$_when" \
                -f 0x10000000 >/dev/null 2>&1; then
            return 0
        fi
        _apk=$(notify_apk_path) || true
        if [ -n "$_apk" ] && [ -x "$APP_PROCESS" ]; then
            if CLASSPATH="$_apk" "$APP_PROCESS" /system/bin --nice-name=install-detect \
                    app.firewall.notify.NotifyRunner "$_pkg" install_detect >/dev/null 2>&1; then
                return 0
            fi
        fi
    fi

    # Fallback: cmd posts to shell_cmd (often hidden — enable Shell app notifications).
    _CMD="${CMD:-/system/bin/cmd}"
    [ -x "$_CMD" ] || _CMD=cmd
    _title="New user app installed"
    _text="$_when - $_pkg"
    _tag="install_detect_${_pkg}"
    if [ "$(id -u 2>/dev/null)" = "0" ]; then
        "$_CMD" notification post -t "$_title" -S bigtext "$_tag" "$_text" >/dev/null 2>&1 && return 0
    fi
    /system/bin/su 2000 "$_CMD" notification post -t "$_title" -S bigtext "$_tag" "$_text" \
        >/dev/null 2>&1
}

detect_new() {
    pm list packages -3 2>/dev/null | sed 's/^package://' | sort -u >"$CUR"
    comm -23 "$CUR" "$BASE" 2>/dev/null | while read -r p; do
        [ -n "$p" ] || continue
        notify_new_pkg "$p" || printf '%s NEW %s (notify failed)\n' "$(date +%H:%M:%S)" "$p" >&2
    done
    cp "$CUR" "$BASE"
}

is_package_db_event() {
    for _arg in "$@"; do
        case "$_arg" in
            packages.xml|packages.list|*/packages.xml|*/packages.list)
                return 0
                ;;
        esac
    done
    return 1
}

# inotifyd callback (invoked with event args, not as "sh script").
if [ $# -gt 0 ]; then
    if is_package_db_event "$@"; then
        detect_new
    fi
    exit 0
fi

command -v inotifyd >/dev/null 2>&1 || {
    echo "inotifyd not found" >&2
    exit 1
}

_src=/data/local/tmp/install-detect-inotify.sh
if [ -f "$0" ] && [ "$0" != "sh" ]; then
    _src="$0"
elif [ -f "${1:-}" ]; then
    _src="$1"
fi

mkdir -p /data/adb/firewall_default_deny
cp "$_src" "$RUNNER"
chmod 755 "$RUNNER"

if ! pm path "$NOTIFY_PKG" >/dev/null 2>&1; then
    echo "WARN: $NOTIFY_PKG not installed; notifications may be hidden (Shell channel)" >&2
fi

pm list packages -3 2>/dev/null | sed 's/^package://' | sort -u >"$BASE"
echo "baseline $(wc -l <"$BASE" | tr -d ' ') user packages; notifications on new installs"
echo "handler: $RUNNER"
echo "watching packages.list + packages.xml (Ctrl+C to stop)"
exec inotifyd "$RUNNER" /data/system/packages.list /data/system/packages.xml
