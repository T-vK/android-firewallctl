# android-firewallctl

Block or allow network access **per app** on a rooted phone, using the same
mechanism as **Settings → Apps → \<app\> → Mobile data & Wi‑Fi**. Changes
show up in the system UI immediately — no VPN, no separate iptables rules.

**What you get**

| Install this | You get |
|---|---|
| **Magisk module** (`firewall_default_deny_*.zip`) | New user apps are blocked by default; tap the notification to allow. |
| **CLI only** (`firewallctl.dex.jar` + wrapper) | Manual `get` / `set` / `clear` from adb, Termux, or scripts. |
| **Termux .deb** | CLI installed under Termux’s prefix. |

> **Root required.** The CLI talks to Android’s network policy service as root.

**Tested with:** LineageOS 23 and Magisk on a Google Pixel 4.
Other ROMs and devices may work — we have not tried them yet. See [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) for details.

---

## Magisk module (recommended)

1. Download **`firewall_default_deny_*.zip`** from [GitHub Releases](https://github.com/T-vK/android-firewallctl/releases) (or build with `make magisk`).
2. Magisk → **Modules** → Install from storage → **Reboot**.
3. Install a new app from the store. You should get a notification that it was blocked; use **Allow** (or clear the block in Settings).

The watcher keeps the list of known third-party apps **in memory only** (not
`known.txt`). On each package-database change it blocks new installs with
`firewallctl set <pkg> +REJECT_ALL` and shows a **FirewallNotify** notification.

**Exempt a sideloaded app** (optional): edit  
`/data/adb/firewall_default_deny/allowlist.txt` — one package name per line, `#` for comments.  
This file is **only** for apps you install by hand; the module never writes it.  
Changes apply on the next package-database update (e.g. another install), not instantly for already-installed apps.

**Logs:** `/data/adb/firewall_default_deny/watcher.log`  
**More detail:** [docs/STATE.md](docs/STATE.md), [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

---

## CLI only (adb)

```bash
make
adb push build/firewallctl.dex.jar /data/local/tmp/
adb push scripts/firewallctl /data/local/tmp/
adb shell su -c 'chmod 0755 /data/local/tmp/firewallctl'

adb shell su -c '/data/local/tmp/firewallctl list-policies'
adb shell su -c '/data/local/tmp/firewallctl get com.android.chrome'
adb shell su -c '/data/local/tmp/firewallctl set com.android.chrome +REJECT_ALL'
adb shell su -c '/data/local/tmp/firewallctl clear com.android.chrome'
```

Typical flags: `+REJECT_ALL` (block all networks), `-REJECT_ALL` (remove that bit).  
Run `list-policies` on your device to see names your ROM exposes.

---

## Termux

```bash
make deb
# copy firewallctl_*_all.deb to the phone, then in Termux:
dpkg -i firewallctl_*_all.deb
tsu -c 'firewallctl list-policies'
```

---

## Notifications not showing?

On the device as root:

```bash
/system/bin/firewall-watcher --test-notify com.example.someapp
```

Or push and run `scripts/test-firewall-notify.sh` / `scripts/diagnose-firewall-notify.sh`.  
See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

---

## How it works (one paragraph)

Android’s **NetworkPolicyManager** stores per-app rules and applies them in the kernel.  
`firewallctl` sets those rules via the same Binder API the Settings app uses.  
The Magisk module runs a small daemon that notices new third-party installs and calls `firewallctl set <pkg> +REJECT_ALL`, then asks **FirewallNotify** to show an actionable notification.

Deep dive: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

## Build & test (developers)

```bash
make              # firewallctl.dex.jar
make deb          # Termux package
make magisk       # module zip (needs ANDROID_HOME for FirewallNotify.apk)
make test-host    # watcher + shellcheck + doc checks (no Android SDK)
make test         # full suite including packaging (needs SDK)
```

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

---

## Documentation

| Doc | Contents |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components, install detection, notifications |
| [docs/STATE.md](docs/STATE.md) | `/data/adb/firewall_default_deny/` layout |
| [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) | What has been tested, likely requirements |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Logs, diagnostics, common issues |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Building, testing, releases |

---

## License

Apache-2.0 — see [LICENSE](LICENSE).
