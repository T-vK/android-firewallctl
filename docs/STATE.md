# State directory

Default path:

```text
/data/adb/firewall_default_deny/
```

Override for tests with `FIREWALL_STATE_DIR`.

## Files you care about

| File / path | Who writes it | Purpose |
|---|---|---|
| `allowlist.txt` | **You** (manual); empty file created at Magisk install if missing | Package names exempt from auto-block on **new** installs. One per line; `#` comments. Module never modifies this file. |
| `watcher.log` | Watcher | Rotated to last 500 lines on daemon start. Primary debug log. |
| `watcher.pid` | Watcher | PID of running daemon. |

## Runtime files (automatic)

| File / path | Purpose |
|---|---|
| `package_events.fifo` | Wake pipe: `inotifyd` callback → daemon reconcile. |
| `reconcile.lock/` | mkdir lock — only one reconcile at a time. |
| `block_queue` | Packages waiting for `firewallctl set +REJECT_ALL`. |
| `block_worker.lock/` | Block worker mutex. |
| `allow_queue` | Allow requests from notification UI. |
| `.diff_old_baseline` | Short-lived; old baseline during a diff (internal). |
| `.to_block`, `.diff_*` | Temporary diff helpers (internal). |
| `.notify_*` | Temporary notify/cmd output (internal). |

## What is **not** used anymore

| Item | Note |
|---|---|
| **`known.txt`** | **Removed.** Package snapshot is **in-memory only** inside the watcher process. If you see `known.txt` in old docs or `install-detect-benchmark.sh`, ignore it for current module behavior. |

## Allowlist behavior

- Edit `allowlist.txt` with any root-capable editor.
- Changes apply on the **next** package-database event that triggers a reconcile
  (e.g. installing another app), not necessarily immediately for apps already
  on the device.
- **Reinstall** (same package name, new UID) is blocked again even if the name
  is on the allowlist.

## Tunables (environment)

Set in `magisk/service.sh` or export before starting the watcher if you customize the module.

| Variable | Default | Effect |
|---|---|---|
| `FIREWALL_STATE_DIR` | `/data/adb/firewall_default_deny` | State root. |
| `FIREWALL_WATCH_DIR` | `/data/system` | Directory watched by `inotifyd`. |
| `FIREWALL_PACKAGES_LIST` | `/data/system/packages.list` | Fallback UID lookup. |
| `FIREWALL_MIN_USER_PACKAGES` | `5` | Minimum third-party packages before trusting a list. |
| `FIREWALL_MASS_BLOCK_LIMIT` | `10` | Max blocks per reconcile; above → safety skip. |
| `FIREWALL_BLOCK_RETRY_MAX` | `20` | Retries waiting for package in `packages.list`. |
| `FIREWALL_BLOCK_RETRY_DELAY` | `1` | Seconds between block retries. |
| `FIREWALL_NOTIFY_CHANNEL` | `firewall_default_deny` | Notification channel id. |
| `FIREWALL_SKIP_NOTIFY_VERIFY` | unset | Skip `dumpsys` notification verify if set. |
| `FIREWALL_LOG_ALL_WAKES` | `0` | Log every FIFO wake if `1`. |

There is **no periodic package poll** — only `inotifyd` events (plus manual
`firewall-watcher --reconcile`).
