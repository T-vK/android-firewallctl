#!/system/bin/sh
# Event-driven new user-app detector (no poll loop).
# Uses toybox inotifyd on packages.list / packages.xml.
#
#   adb push scripts/install-detect-inotify.sh /data/local/tmp/
#   adb shell su -c 'sh /data/local/tmp/install-detect-inotify.sh'

BASE=/data/local/tmp/.ni_base
CUR=/data/local/tmp/.ni_cur

detect_new() {
    pm list packages -3 2>/dev/null | sed 's/^package://' | sort -u >"$CUR"
    comm -23 "$CUR" "$BASE" 2>/dev/null | while read -r p; do
        [ -n "$p" ] && printf '%s NEW %s\n' "$(date +%H:%M:%S)" "$p"
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

# inotifyd callback (not the initial launcher).
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

pm list packages -3 2>/dev/null | sed 's/^package://' | sort -u >"$BASE"
echo "baseline $(wc -l <"$BASE" | tr -d ' ') user packages; watching packages.list + packages.xml"
echo "install an app; Ctrl+C to stop"
exec inotifyd "$0" /data/system/packages.list /data/system/packages.xml
