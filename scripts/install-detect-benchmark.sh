#!/system/bin/sh
# Benchmark how quickly different signals show a new user app after install.
# Run on device as root (adb shell su -c 'sh /path/install-detect-benchmark.sh').
#
# Usage:
#   install-detect-benchmark.sh              # watch until Ctrl+C
#   install-detect-benchmark.sh com.foo.bar  # also print when this package appears
#
# Install an app from the store while this runs, then compare timestamps.

PKG="${1:-}"
STATE="${FIREWALL_STATE_DIR:-/data/adb/firewall_default_deny}"
KNOWN="$STATE/known.txt"
INTERVAL="${FIREWALL_BENCH_INTERVAL:-0.5}"
WATCH_DIR="${FIREWALL_WATCH_DIR:-/data/system}"

log() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S.%3N' 2>/dev/null || date '+%H:%M:%S')" "$*"
}

baseline_pm() {
    pm list packages -3 2>/dev/null | sed 's/^package://' | sort -u
}

baseline_known() {
    sed 's/ .*//' "$KNOWN" 2>/dev/null | sort -u
}

log "benchmark: watching new user apps (interval ${INTERVAL}s)"
log "known.txt: $KNOWN"
[ -n "$PKG" ] && log "target package: $PKG"
log "install an app now, then compare which line appears first"
echo "---"

_seen_pm=$(mktemp)
_seen_known=$(mktemp)
_seen_plist=0
_seen_pxml=0
_baseline_plist=$(stat -c %Y "$WATCH_DIR/packages.list" 2>/dev/null || echo 0)
_baseline_pxml=$(stat -c %Y "$WATCH_DIR/packages.xml" 2>/dev/null || echo 0)
baseline_pm >"$_seen_pm"
baseline_known >"$_seen_known"

while true; do
    _now_pm=$(baseline_pm)
    _new_pm=$(comm -23 <(echo "$_now_pm") "$(cat "$_seen_pm")" 2>/dev/null)
    if [ -n "$_new_pm" ]; then
        log "pm list -3 NEW: $_new_pm"
        echo "$_now_pm" >"$_seen_pm"
    fi

    _now_known=$(baseline_known)
    _new_known=$(comm -23 <(echo "$_now_pm") "$(cat "$_seen_known")" 2>/dev/null)
    if [ -n "$_new_known" ]; then
        log "not in known.txt (pm -3 vs snapshot names): $_new_known"
        echo "$_now_known" >"$_seen_known"
    fi

    _pl=$(stat -c %Y "$WATCH_DIR/packages.list" 2>/dev/null || echo 0)
    if [ "$_pl" != "$_baseline_plist" ] && [ "$_seen_plist" = 0 ]; then
        _seen_plist=1
        log "packages.list mtime changed (was $_baseline_plist now $_pl)"
        _baseline_plist=$_pl
    fi

    _px=$(stat -c %Y "$WATCH_DIR/packages.xml" 2>/dev/null || echo 0)
    if [ "$_px" != "$_baseline_pxml" ] && [ "$_seen_pxml" = 0 ]; then
        _seen_pxml=1
        log "packages.xml mtime changed (was $_baseline_pxml now $_px)"
        _baseline_pxml=$_px
    fi

    if [ -n "$PKG" ]; then
        if pm list packages -3 2>/dev/null | sed 's/^package://' | grep -qxF "$PKG"; then
            if [ ! -f "$STATE/.bench_seen_$PKG" ]; then
                log "TARGET $PKG visible in pm list -3"
                touch "$STATE/.bench_seen_$PKG"
            fi
        fi
        if [ -f "$KNOWN" ] && sed 's/ .*//' "$KNOWN" | grep -qxF "$PKG"; then
            if [ ! -f "$STATE/.bench_known_$PKG" ]; then
                log "TARGET $PKG recorded in known.txt"
                touch "$STATE/.bench_known_$PKG"
            fi
        fi
        if [ -f "$STATE/watcher.log" ] && grep -q "blocked $PKG\|reconcile:.*$PKG" "$STATE/watcher.log" 2>/dev/null; then
            if [ ! -f "$STATE/.bench_blocked_$PKG" ]; then
                log "TARGET $PKG in watcher.log (blocked/reconcile)"
                touch "$STATE/.bench_blocked_$PKG"
            fi
        fi
    fi

    sleep "$INTERVAL"
done
