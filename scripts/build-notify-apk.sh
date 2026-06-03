#!/usr/bin/env bash
# Build FirewallNotify.apk (system app for Magisk module notifications).
# Requires ANDROID_HOME with platforms;android-34 and build-tools installed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/build}"
APK_OUT="$OUT_DIR/FirewallNotify.apk"
STAGE="$OUT_DIR/notify-apk-staging"
MANIFEST="$ROOT/src/notify/AndroidManifest.xml"
RES_DIR="$ROOT/src/notify/res"
SRC_DIR="$ROOT/src/notify/app/firewall/notify"

SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$SDK_ROOT" ] || [ ! -d "$SDK_ROOT" ]; then
    echo "build-notify-apk: ANDROID_HOME not set or missing" >&2
    exit 1
fi

PLATFORM_JAR="$(ls -1d "$SDK_ROOT"/platforms/android-3*/android.jar 2>/dev/null | sort -V | tail -1)"
BT_DIR="$(ls -1d "$SDK_ROOT"/build-tools/*/ 2>/dev/null | sort -V | tail -1)"
if [ -z "$PLATFORM_JAR" ] || [ ! -f "$PLATFORM_JAR" ]; then
    echo "build-notify-apk: install platforms;android-34 (sdkmanager)" >&2
    exit 1
fi
if [ -z "$BT_DIR" ]; then
    echo "build-notify-apk: install build-tools (sdkmanager)" >&2
    exit 1
fi

AAPT="$BT_DIR/aapt"
D8="$BT_DIR/d8"
APKSIGNER="$BT_DIR/apksigner"
ZIPALIGN="$BT_DIR/zipalign"
KEYSTORE="$OUT_DIR/notify-debug.keystore"

command -v javac >/dev/null 2>&1 || { echo "build-notify-apk: javac required" >&2; exit 1; }
for tool in "$AAPT" "$D8" "$APKSIGNER" "$ZIPALIGN"; do
    if [ ! -x "$tool" ]; then
        echo "build-notify-apk: missing $tool" >&2
        exit 1
    fi
done

rm -rf "$STAGE"
mkdir -p "$STAGE/classes"

echo "  JAVAC    notify APK sources"
javac -source 1.8 -target 1.8 -Xlint:-options \
    -bootclasspath "$PLATFORM_JAR" \
    -d "$STAGE/classes" \
    "$SRC_DIR"/*.java

echo "  D8       classes -> classes.dex"
mapfile -t CLASS_FILES < <(find "$STAGE/classes" -name '*.class' -print)
if [ "${#CLASS_FILES[@]}" -eq 0 ]; then
    echo "build-notify-apk: no .class files produced" >&2
    exit 1
fi
"$D8" --min-api 26 --output "$STAGE" "${CLASS_FILES[@]}"
rm -rf "$STAGE/classes"

echo "  AAPT     package manifest + resources"
"$AAPT" package -f \
    -M "$MANIFEST" \
    -S "$RES_DIR" \
    -I "$PLATFORM_JAR" \
    -F "$STAGE/unsigned.apk"

echo "  AAPT     add classes.dex"
(cd "$STAGE" && "$AAPT" add unsigned.apk classes.dex >/dev/null)

if [ ! -f "$KEYSTORE" ]; then
    echo "  KEYTOOL  debug keystore for notify APK"
    keytool -genkeypair -noprompt \
        -keystore "$KEYSTORE" \
        -storepass android \
        -keypass android \
        -alias notify \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=Firewall Notify,O=Firewall,C=US"
fi

ALIGNED="$STAGE/aligned.apk"
"$ZIPALIGN" -f 4 "$STAGE/unsigned.apk" "$ALIGNED"
"$APKSIGNER" sign \
    --ks "$KEYSTORE" \
    --ks-pass pass:android \
    --key-pass pass:android \
    --ks-key-alias notify \
    --out "$APK_OUT" \
    "$ALIGNED"

rm -rf "$STAGE"
echo "Built: $APK_OUT"
