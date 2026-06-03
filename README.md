# android-firewallctl

Per-app Android firewall control for rooted devices, driven through the
real `NetworkPolicyManager` so changes show up in the system Settings UI
(LineageOS/AOSP "Apps → \<app\> → Mobile data & Wi-Fi"). No VPN, no
iptables hooks, no separate state to drift out of sync.

The project ships three artifacts:

| Artifact | What it is | Where it lands |
|---|---|---|
| `firewallctl.dex.jar` + wrapper | A reflection-based CLI that talks to `INetworkPolicyManager` via `app_process`. | `/data/local/tmp/` or `$PREFIX/bin/` (Termux) |
| `firewallctl_*.deb` | Termux-compatible Debian package of the CLI. | `dpkg -i` inside Termux |
| `firewall_default_deny_*.zip` | Magisk module that ships the CLI and an `inotifyd`-based watcher that auto-blocks Internet for every newly installed user app. | Magisk Manager → Install from storage |

> **Requires root.** The CLI talks to a `signature|privileged` system
> service via `app_process`; this only works as root. Tested against
> LineageOS 20+.

---

## Quick start (the CLI)

```bash
make                       # build build/firewallctl.dex.jar
adb push build/firewallctl.dex.jar /data/local/tmp/
adb push scripts/firewallctl /data/local/tmp/
adb shell su -c 'chmod 0755 /data/local/tmp/firewallctl'

adb shell su -c '/data/local/tmp/firewallctl list-policies'
adb shell su -c '/data/local/tmp/firewallctl get  com.android.chrome'
adb shell su -c '/data/local/tmp/firewallctl set  com.android.chrome +REJECT_ALL'
adb shell su -c '/data/local/tmp/firewallctl clear com.android.chrome'
```

Available policy flags mirror the system constants — `REJECT_METERED`,
`ALLOW_METERED`, `REJECT_ALL`, plus anything else exposed by the local
`NetworkPolicyManager` (resolved reflectively at runtime so the CLI
stays compatible across Lineage versions).

## Quick start (Termux .deb)

```bash
make deb
adb push build/firewallctl_*_all.deb /sdcard/Download/
# in Termux:
mv ~/storage/downloads/firewallctl_*_all.deb .
dpkg -i firewallctl_*_all.deb
tsu -c 'firewallctl list-policies'
```

## Quick start (Magisk module: default-deny for new apps)

```bash
make magisk
adb push build/firewall_default_deny_*.zip /sdcard/
# Magisk Manager → Modules → Install from storage → reboot
```

After reboot, a watcher daemon runs as root. It:

1. Watches `/data/system/` via `inotifyd`. When `packages.xml` changes
   (i.e. PMS just committed an install), it reconciles `pm list packages -3`
   against a snapshot at `/data/adb/firewall_default_deny/known.txt`.
2. For each new third-party package not on the allowlist, it invokes
   `firewallctl set <pkg> +REJECT_ALL`. The change is **immediately
   reflected in the system Settings UI**.
3. Shows an actionable notification (Allow network / Network settings) via
   the bundled `FirewallNotify` system app (`app.firewall.notify`), with
   `su 2000 cmd notification` and `am start` fallbacks if the APK is missing.
4. End-to-end latency from `close_write` on `packages.xml` to policy
   applied is typically 150–400 ms — fast enough to win the race against
   most "Open" taps post-install.


### Allowlist

Plain text, one package per line, `#` for comments:

```
/data/adb/firewall_default_deny/allowlist.txt
```

Edits take effect on the next install event — no restart required.

### State directory

```
/data/adb/firewall_default_deny/
├── allowlist.txt        # user-editable
├── known.txt            # snapshot of third-party packages
├── reconcile.lock/      # transient (mkdir) lock during reconcile
└── watcher.log          # daemon log (trimmed to 500 lines on each start)
```

### Tunables

| Env var | Default | Effect |
|---|---|---|
| `FIREWALL_STATE_DIR` | `/data/adb/firewall_default_deny` | State directory location. Mainly for tests. |
| `FIREWALL_WATCH_DIR` | `/data/system` | Directory watched by `inotifyd`. |
| `FIREWALL_WATCHER_SAFETY_INTERVAL` | `300` | Safety-net poll period in seconds. The hot path is event-driven; this is belt-and-suspenders. |

Set them in `service.sh` if you want different defaults baked into the
module.

---

## How it works (short version)

The Settings toggles for per-app data restrictions are surfaced by
`NetworkPolicyManagerService`. The UI calls
`NetworkPolicyManager.setUidPolicy(uid, mask)`; NPMS programs `netd`
(iptables/eBPF) and persists the policy bits. Any "firewall" that
manipulates iptables directly (AFWall+, NetBlock, Net Switch, …) ends
up out of sync with that UI because the policy bits NPMS knows about
never change.

`firewallctl` calls the *same* `setUidPolicy` entrypoint, via Binder
reflection from an `app_process` host. The settings UI sees the change
immediately, because there's only one source of truth.

The Magisk module wraps the CLI in an `inotifyd`-driven watcher so that
"default deny for new installs" is just a series of `setUidPolicy`
calls — no Xposed hooks, no VPN, no extra netfilter rules.

For the design discussion and gotchas (broadcast races, atomic-file
write semantics, why we watch the directory not the file), see the
inline comments in `magisk/system/bin/firewall-watcher`.

---

## Build

Requirements: `make`, `javac` (OpenJDK 8+), `zip`, `unzip`, `dpkg-dev`,
and either `d8`/`dx` from the Android SDK build-tools **or** an internet
connection (the Makefile fetches R8 on demand; R8 needs Java 11+).

```bash
make           # build/firewallctl.dex.jar
make deb       # build/firewallctl_<ver>_all.deb
make magisk    # build/firewall_default_deny_<ver>.zip
make test      # run the host test suite (auto-builds artifacts first)
make clean
```

## Tests

Host-side tests live in `tests/` and run on every push via GitHub
Actions:

| File | What it checks |
|---|---|
| `tests/test-watcher.sh` | Functional tests of `firewall-watcher` driven through `--reconcile` and `inotifyd`-style callback args, with stub `pm`/`firewallctl`/`cmd` on `PATH`. Covers initial snapshot, new-install detection, allowlist skip, callback filename filter, and lockfile serialization. |
| `tests/test-packaging.sh` | Structural assertions on the built `.deb` (Termux prefix paths, correct CLASSPATH inside the wrapper) and Magisk zip (required entries, `module.prop` fields, valid DEX magic in the dex jar). |
| `tests/test-shellcheck.sh` | Shellcheck across every shell script in the repo. |

Add a new check by dropping a `tests/test-*.sh` into the directory —
`tests/run-tests.sh` auto-discovers it.

## CI & releases

`.github/workflows/ci.yml` runs on every push and PR:

- Builds dex jar, `.deb`, and Magisk zip.
- Runs the host test suite.
- Uploads all three artifacts to the workflow run.

Versioning and releases are fully automated with
[semantic-release](https://semantic-release.gitbook.io/). On every push
to `main`, the `release` job inspects the
[Conventional Commits](https://www.conventionalcommits.org/) since the
last release and:

- Computes the next [SemVer](https://semver.org/) version
  (`fix:`/`perf:` → patch, `feat:` → minor, `BREAKING CHANGE:` → major).
- Builds version-stamped artifacts via `make dist VERSION=<next>`:
  `firewallctl-<ver>.dex.jar`, `firewallctl_<ver>_all.deb`, and
  `firewall_default_deny_v<ver>.zip` (the Magisk `module.prop`
  `version`/`versionCode` are stamped to match).
- Tags the commit `v<ver>` and publishes a GitHub Release with
  auto-generated notes and the three artifacts attached.

If no commits since the last release warrant a version bump, no release
is produced. Commit messages therefore drive the entire release: use
`feat:`, `fix:`, `perf:`, `docs:`, `chore:`, etc.

---

## License

Apache-2.0. See [LICENSE](LICENSE). No proprietary Google libraries are
used at build time or at runtime; the dex backend (R8) is itself
Apache-2.0.


**Allow network** on the notification does not call Magisk su from the app (you
will not get a superuser prompt for Firewall Notify). It queues the package for
the root **firewall-watcher**, which runs `firewall-allow-app` within a few
seconds.

