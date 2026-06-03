# firewallctl build system
#
# Dependencies (all Apache-2.0 / FOSS, no Google proprietary blobs needed):
#   - javac    (OpenJDK 8 or newer; any distro's openjdk-*-jdk package)
#   - d8       (or dx) from Android SDK build-tools; also shipped standalone in
#              many distros as `android-tools` / `dexlib2-utils` etc.
#              Source: https://r8.googlesource.com/r8 (Apache-2.0)
#
# Magisk notifications additionally need ANDROID_HOME with platforms;android-34
# and build-tools (aapt, d8, apksigner) — see scripts/build-notify-apk.sh.
#
# Usage:
#   make             # builds build/firewallctl.dex.jar
#   make install     # adb push to /data/local/tmp/ and chmod
#   make run ARGS="get com.android.chrome"
#   make deb         # build a Termux-compatible .deb (requires dpkg-dev)
#   make clean
#
# The CLI is a self-contained dex jar plus a tiny shell wrapper.
# The Magisk zip also ships FirewallNotify.apk as a system app.

PACKAGE      := app.firewallctl
MAIN_CLASS   := $(PACKAGE).Main

SRC_DIR      := src
SCRIPTS_DIR  := scripts
OUT_DIR      := build
CLASSES_DIR  := $(OUT_DIR)/classes
JAR          := $(OUT_DIR)/firewallctl-classes.jar
DEX_JAR      := $(OUT_DIR)/firewallctl.dex.jar
NOTIFY_APK   := $(OUT_DIR)/FirewallNotify.apk
WRAPPER_SRC  := $(SCRIPTS_DIR)/firewallctl
MAGISK_DIR   := magisk

# Single source of truth for the release version. CI (semantic-release)
# passes VERSION=X.Y.Z on the command line; local builds default to 0.0.0.
VERSION      ?= 0.0.0
# Magisk versionCode must be a monotonically increasing integer. Derive it
# from the semver (any prerelease suffix is stripped first).
CLEAN_VER    := $(firstword $(subst -, ,$(VERSION)))
VERSION_CODE := $(shell echo $(CLEAN_VER) | awk -F. '{printf "%d", ($$1*1000000)+($$2*1000)+$$3}')

MAGISK_ZIP   := $(OUT_DIR)/firewall_default_deny_v$(VERSION).zip
DIST_DEX_JAR := $(OUT_DIR)/firewallctl-$(VERSION).dex.jar

CORE_SRCS    := $(SRC_DIR)/app/firewallctl/Main.java

# Tool discovery: prefer PATH, then $ANDROID_HOME / $ANDROID_SDK_ROOT.
# If neither d8 nor dx is found, the build will fetch R8 from Maven Central.
# R8 is Apache-2.0; source: https://r8.googlesource.com/r8 .
JAVAC ?= javac
JAR_TOOL ?= jar
D8 ?= $(shell command -v d8 2>/dev/null || \
              ls -1 $${ANDROID_HOME:-/opt/android-sdk}/build-tools/*/d8 2>/dev/null | sort -V | tail -1)
DX ?= $(shell command -v dx 2>/dev/null || \
              ls -1 $${ANDROID_HOME:-/opt/android-sdk}/build-tools/*/dx 2>/dev/null | sort -V | tail -1)

R8_VERSION ?= 8.5.35
R8_JAR     := $(OUT_DIR)/r8-$(R8_VERSION).jar
# Official Google-hosted R8 binary release (Apache-2.0; source: r8.googlesource.com/r8).
R8_URL     := https://storage.googleapis.com/r8-releases/raw/$(R8_VERSION)/r8.jar
# R8 8.x requires Java 11+ to run. Source compilation still targets 1.8 bytecode.
JAVA_R8    ?= $(firstword $(shell \
                for j in /usr/lib/jvm/java-21-openjdk-amd64/bin/java \
                         /usr/lib/jvm/java-17-openjdk-amd64/bin/java \
                         /usr/lib/jvm/java-11-openjdk-amd64/bin/java \
                         /usr/lib/jvm/default-java/bin/java; do \
                  if [ -x "$$j" ] && "$$j" -version 2>&1 | head -1 | \
                     grep -qE 'version "(1[1-9]|[2-9][0-9])'; then \
                    echo "$$j"; exit 0; \
                  fi; \
                done; \
                command -v java 2>/dev/null))

# Device install location.
DEVICE_DIR   ?= /data/local/tmp
ADB          ?= adb

.PHONY: all clean install uninstall run deb magisk dist test check-tools notify-apk

all: $(DEX_JAR)

check-tools:
	@command -v $(JAVAC) >/dev/null 2>&1 || { echo "error: javac not found (install openjdk-*-jdk)"; exit 1; }

$(R8_JAR):
	@mkdir -p $(OUT_DIR)
	@echo "  FETCH    $(R8_URL)"
	@curl -fsSL -o $@ $(R8_URL) || wget -qO $@ $(R8_URL)

$(CLASSES_DIR)/.stamp: $(CORE_SRCS)
	@mkdir -p $(CLASSES_DIR)
	$(JAVAC) -source 1.8 -target 1.8 -Xlint:-options -d $(CLASSES_DIR) $(CORE_SRCS)
	@touch $@

$(JAR): $(CLASSES_DIR)/.stamp
	@cd $(CLASSES_DIR) && $(JAR_TOOL) cf $(abspath $@) .

$(DEX_JAR): $(JAR) check-tools
	@mkdir -p $(OUT_DIR)
	@if [ -n "$(D8)" ]; then \
	    echo "  D8       $(JAR) -> $(DEX_JAR)"; \
	    $(D8) --min-api 26 --output $(OUT_DIR) $(JAR); \
	elif [ -n "$(DX)" ]; then \
	    echo "  DX       $(JAR) -> $(DEX_JAR)"; \
	    $(DX) --dex --output=$(OUT_DIR)/classes.dex $(JAR); \
	else \
	    $(MAKE) --no-print-directory $(R8_JAR); \
	    if [ -z "$(JAVA_R8)" ]; then \
	        echo "error: R8 needs Java 11+; install openjdk-11-jre-headless (or set JAVA_R8=/path/to/java)"; \
	        exit 1; \
	    fi; \
	    echo "  R8.D8    $(JAR) -> $(DEX_JAR)   (using $(JAVA_R8))"; \
	    $(JAVA_R8) -cp $(R8_JAR) com.android.tools.r8.D8 --min-api 26 --output $(OUT_DIR) $(JAR); \
	fi
	@(cd $(OUT_DIR) && $(JAR_TOOL) cf $(notdir $(DEX_JAR)) classes.dex && rm -f classes.dex)
	@echo "Built: $(DEX_JAR)"

notify-apk:
	@$(SCRIPTS_DIR)/build-notify-apk.sh $(OUT_DIR)

$(NOTIFY_APK): $(wildcard src/notify/app/firewall/notify/*.java) src/notify/AndroidManifest.xml scripts/build-notify-apk.sh
	@$(MAKE) --no-print-directory notify-apk

install: $(DEX_JAR) $(WRAPPER_SRC)
	$(ADB) push $(DEX_JAR)    $(DEVICE_DIR)/firewallctl.dex.jar
	$(ADB) push $(WRAPPER_SRC) $(DEVICE_DIR)/firewallctl
	$(ADB) shell chmod 0755 $(DEVICE_DIR)/firewallctl
	@echo
	@echo "Installed. Run on device with:"
	@echo "  adb shell su -c '$(DEVICE_DIR)/firewallctl <args>'"

uninstall:
	$(ADB) shell rm -f $(DEVICE_DIR)/firewallctl.dex.jar $(DEVICE_DIR)/firewallctl

run: install
	$(ADB) shell su -c "$(DEVICE_DIR)/firewallctl $(ARGS)"

deb: $(DEX_JAR)
	$(SCRIPTS_DIR)/make-deb.sh $(VERSION)

# Magisk module: CLI, watcher, notify APK, allow helper script.
magisk: $(DEX_JAR) $(NOTIFY_APK) $(WRAPPER_SRC) $(MAGISK_DIR)/module.prop
	@command -v zip >/dev/null 2>&1 || { echo "error: zip not found (install zip)"; exit 1; }
	@rm -rf $(OUT_DIR)/magisk-staging
	@mkdir -p $(OUT_DIR)/magisk-staging/system/bin \
	          $(OUT_DIR)/magisk-staging/system/priv-app/FirewallNotify \
	          $(OUT_DIR)/magisk-staging/system/etc/permissions
	@sed -e 's/^version=.*/version=v$(VERSION)/' \
	     -e 's/^versionCode=.*/versionCode=$(VERSION_CODE)/' \
	     $(MAGISK_DIR)/module.prop > $(OUT_DIR)/magisk-staging/module.prop
	@cp $(MAGISK_DIR)/service.sh       $(OUT_DIR)/magisk-staging/service.sh
	@cp $(MAGISK_DIR)/customize.sh     $(OUT_DIR)/magisk-staging/customize.sh
	@cp $(MAGISK_DIR)/uninstall.sh     $(OUT_DIR)/magisk-staging/uninstall.sh
	@cp $(WRAPPER_SRC)                 $(OUT_DIR)/magisk-staging/system/bin/firewallctl
	@cp $(DEX_JAR)                     $(OUT_DIR)/magisk-staging/system/bin/firewallctl.dex.jar
	@cp $(MAGISK_DIR)/system/bin/firewall-watcher \
	     $(OUT_DIR)/magisk-staging/system/bin/firewall-watcher
	@cp $(MAGISK_DIR)/system/bin/firewall-allow-app \
	     $(OUT_DIR)/magisk-staging/system/bin/firewall-allow-app
	@cp $(NOTIFY_APK)                  $(OUT_DIR)/magisk-staging/system/priv-app/FirewallNotify/FirewallNotify.apk
	@cp $(MAGISK_DIR)/system/etc/permissions/privapp-permissions-app.firewall.notify.xml \
	     $(OUT_DIR)/magisk-staging/system/etc/permissions/privapp-permissions-app.firewall.notify.xml
	@cp $(NOTIFY_APK)                  $(OUT_DIR)/magisk-staging/FirewallNotify.apk
	@chmod 0755 $(OUT_DIR)/magisk-staging/service.sh \
	            $(OUT_DIR)/magisk-staging/customize.sh \
	            $(OUT_DIR)/magisk-staging/uninstall.sh \
	            $(OUT_DIR)/magisk-staging/system/bin/firewallctl \
	            $(OUT_DIR)/magisk-staging/system/bin/firewall-watcher \
	            $(OUT_DIR)/magisk-staging/system/bin/firewall-allow-app
	@rm -f $(MAGISK_ZIP)
	@(cd $(OUT_DIR)/magisk-staging && zip -qr ../$(notdir $(MAGISK_ZIP)) .)
	@echo "Built: $(MAGISK_ZIP)"

# Build every release artifact with the version baked into its filename.
# Driven by semantic-release in CI via: make dist VERSION=$(NEXT_VERSION)
dist: $(DEX_JAR) deb magisk
	@cp $(DEX_JAR) $(DIST_DEX_JAR)
	@echo "Release artifacts for v$(VERSION):"
	@ls -1 $(DIST_DEX_JAR) $(OUT_DIR)/firewallctl_$(VERSION)_all.deb $(MAGISK_ZIP)

# Run the host-side test suite. Builds the dex jar, .deb and Magisk zip
# first so the packaging assertions have artifacts to inspect.
test: $(DEX_JAR) deb magisk
	@bash tests/run-tests.sh

clean:
	rm -rf $(OUT_DIR)
