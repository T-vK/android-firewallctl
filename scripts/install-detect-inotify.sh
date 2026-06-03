#!/system/bin/sh
# Event-driven new user-app detector (no poll loop).
# Posts a notification for each newly seen user app.
#
#   adb push scripts/install-detect-inotify.sh /data/local/tmp/
#   adb shell su -c 'sh /data/local/tmp/install-detect-inotify.sh'
#
# inotifyd must exec the handler; /data/local/tmp is often noexec (Permission denied).
# This script installs a copy under /data/adb/ and runs inotifyd on that path.

BASE=/data/local/tmp/.ni_base
CUR=/data/local/tmp/.ni_cur
RUNNER=/data/adb/firewall_default_deny/install-detect-inotify.sh
CMD="${CMD:-/system/bin/cmd}"
[ -x "$CMD" ] || CMD=cmd

notify_new_pkg() {
    _pkg="$1"
    [ -n "$_pkg" ] || return 1
    _when=$(date '+%H:%M:%S' 2>/dev/null || date)
    _title="New user app installed"
    _text="$_when — $_pkg"
    _tag="install_detect_${_pkg}"
    _intent="intent:#Intent;action=android.settings.APPLICATION_DETAILS_SETTINGS;data=package:${_pkg};end"

    if [ "$(id -u 2>/dev/null)" = "0" ]; then
        "$CMD" notification post -t "$_title" -c "$_intent" "$_tag" "$_text" 2>/dev/null && return 0
    fi
    if [ -x /system/bin/su ]; then
        /system/bin/su 2000 "$CMD" notification post -t "$_title" -c "$_intent" "$_tag" "$_text" \
            2>/dev/null && return 0
    fi
    "$CMD" notification post -t "$_title" -c "$_intent" "$_tag" "$_text" 2>/dev/null
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

pm list packages -3 2>/dev/null | sed 's/^package://' | sort -u >"$BASE"
echo "baseline $(wc -l <"$BASE" | tr -d ' ') user packages; notifications on new installs"
echo "handler: $RUNNER"
echo "watching packages.list + packages.xml (Ctrl+C to stop)"
exec inotifyd "$RUNNER" /data/system/packages.list /data/system/packages.xml
