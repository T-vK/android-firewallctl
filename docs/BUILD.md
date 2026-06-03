# Building from source

Use this guide if you want to compile artifacts yourself instead of downloading
[GitHub Releases](https://github.com/T-vK/android-firewallctl/releases).

For installing pre-built releases on a device, see the [README](../README.md).

## Prerequisites

| Tool | Used for |
|---|---|
| `make`, `javac` (8+) | CLI dex jar |
| `zip`, `unzip`, `dpkg-dev` | Magisk zip, Termux `.deb` |
| `d8` / `dx` **or** network + Java 11+ | DEX (Makefile can fetch R8) |
| **ANDROID_HOME** + SDK 34 platform & build-tools | `FirewallNotify.apk` (Magisk module only) |

## Build targets

```bash
make              # build/firewallctl.dex.jar
make deb          # build/firewallctl_<version>_all.deb
make magisk       # build/firewall_default_deny_v<version>.zip
make dist VERSION=1.2.3   # version-stamped release artifacts (as CI does)
make clean
```

`VERSION` defaults to `0.0.0` on local builds. Releases use the version from
[semantic-release](https://semantic-release.gitbook.io/) on `main`.

## Components

| Target | Output | Contents |
|---|---|---|
| `make` (default) | `build/firewallctl.dex.jar` | CLI bytecode; pair with `scripts/firewallctl` wrapper on device |
| `make deb` | `build/firewallctl_*_all.deb` | Termux install: wrapper + jar under Termux prefix |
| `make magisk` | `build/firewall_default_deny_v*.zip` | Module: CLI, watcher, allow helper, FirewallNotify priv-app |

Building the Magisk zip requires `make magisk`, which depends on
`scripts/build-notify-apk.sh` (Android SDK).

## Install built CLI to a connected device (adb)

```bash
make install          # push jar + wrapper to /data/local/tmp/
make run ARGS="list-policies"
```

Or push manually:

```bash
adb push build/firewallctl.dex.jar /data/local/tmp/
adb push scripts/firewallctl /data/local/tmp/
adb shell su -c 'chmod 0755 /data/local/tmp/firewallctl'
```

## Tests

See [DEVELOPMENT.md](DEVELOPMENT.md) for `make test-host` and `make test`.

## Project layout

```text
src/app/firewallctl/Main.java     # CLI
src/notify/                       # FirewallNotify APK sources
magisk/                           # Module template
scripts/                          # firewallctl wrapper, build-notify-apk.sh, diagnostics
tests/                            # Host test scripts
```
