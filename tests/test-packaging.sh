#!/usr/bin/env bash
# Structural checks on the built artifacts. Assumes `make deb` and
# `make magisk` have already been run (the `test` Makefile target chains
# them). Validates internal layout without needing an Android device.

set -u

: "${PROJECT_DIR:=$(cd "$(dirname "$0")/.." && pwd)}"
BUILD_DIR="$PROJECT_DIR/build"

fail=0
assert() {
    if ! eval "$2"; then
        printf '   - assert failed: %s\n' "$1" >&2
        fail=1
    fi
}

# ----- dex jar -----
DEX_JAR="$BUILD_DIR/firewallctl.dex.jar"
assert "dex jar exists" "[ -f '$DEX_JAR' ]"
if [ -f "$DEX_JAR" ]; then
    unzip -p "$DEX_JAR" classes.dex > "$BUILD_DIR/.classes.dex" 2>/dev/null || true
    assert "dex jar contains classes.dex" "[ -s '$BUILD_DIR/.classes.dex' ]"
    # DEX magic is "dex\n<ver>\0", e.g. "dex\n038\0".
    assert "classes.dex has valid DEX magic" \
        "head -c 4 '$BUILD_DIR/.classes.dex' | grep -q '^dex'"
    rm -f "$BUILD_DIR/.classes.dex"
fi

# ----- termux .deb -----
# shellcheck disable=SC2012  # globbing here is fine; filenames are controlled.
DEB="$(ls -1 "$BUILD_DIR"/firewallctl_*_all.deb 2>/dev/null | head -1)"
assert ".deb exists" "[ -n '$DEB' ]"
if [ -n "$DEB" ] && [ -f "$DEB" ]; then
    # shellcheck disable=SC2034  # consumed via eval in assert
    files="$(dpkg-deb --contents "$DEB" | awk '{print $NF}')"
    assert ".deb installs firewallctl wrapper at Termux prefix" \
        "echo \"\$files\" | grep -qF './data/data/com.termux/files/usr/bin/firewallctl'"
    assert ".deb installs dex jar at Termux lib prefix" \
        "echo \"\$files\" | grep -qF './data/data/com.termux/files/usr/lib/firewallctl/firewallctl.dex.jar'"
    # shellcheck disable=SC2034  # consumed via eval in assert
    wrapper="$(dpkg-deb --fsys-tarfile "$DEB" \
        | tar -xOf - ./data/data/com.termux/files/usr/bin/firewallctl)"
    assert ".deb wrapper exports correct CLASSPATH" \
        "echo \"\$wrapper\" | grep -qF '/data/data/com.termux/files/usr/lib/firewallctl/firewallctl.dex.jar'"
    assert ".deb wrapper invokes app_process" \
        "echo \"\$wrapper\" | grep -qF 'exec app_process'"
fi

# ----- magisk module zip -----
# shellcheck disable=SC2012
ZIP="$(ls -1 "$BUILD_DIR"/firewall_default_deny_*.zip 2>/dev/null | head -1)"
assert "magisk zip exists" "[ -n '$ZIP' ]"
if [ -n "$ZIP" ] && [ -f "$ZIP" ]; then
    # shellcheck disable=SC2034  # consumed via eval in assert
    entries="$(unzip -Z1 "$ZIP")"
    for required in \
        module.prop customize.sh service.sh uninstall.sh \
        system/bin/firewallctl system/bin/firewallctl.dex.jar \
        system/bin/firewall-watcher system/bin/firewall-allow-app \
        FirewallNotify.apk
    do
        assert "magisk zip contains $required" \
            "echo \"\$entries\" | grep -qFx '$required'"
    done
    # module.prop must declare id and version.
    propfile="$(mktemp)"
    unzip -p "$ZIP" module.prop > "$propfile"
    assert "module.prop has id=firewall_default_deny" \
        "grep -q '^id=firewall_default_deny\$' '$propfile'"
    assert "module.prop has version field" "grep -q '^version=' '$propfile'"
    assert "module.prop has versionCode field" "grep -q '^versionCode=' '$propfile'"
    rm -f "$propfile"
fi

exit "$fail"
