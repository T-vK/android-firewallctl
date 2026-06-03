# Troubleshooting

## Magisk module installed but nothing blocks new apps

1. Confirm the module is **enabled** and you **rebooted** after install.
2. Check the watcher is running:
   ```bash
   adb shell su -c 'cat /data/adb/firewall_default_deny/watcher.pid'
   adb shell su -c 'kill -0 $(cat /data/adb/firewall_default_deny/watcher.pid) && echo running'
   ```
3. Read the log:
   ```bash
   adb shell su -c 'tail -50 /data/adb/firewall_default_deny/watcher.log'
   ```
   Look for `firewall-watcher build=memdiff-…`, `baseline:`, `blocked`, or `SAFETY:` lines.
4. Verify CLI works:
   ```bash
   adb shell su -c 'firewallctl list-policies'
   adb shell su -c 'firewallctl get com.android.chrome'
   ```
5. If log says `inotifyd not in PATH`, your ROM may lack `inotifyd` — install detection will not run until that is fixed.

## Notifications missing

1. Test the full notify pipeline (root):
   ```bash
   adb shell su -c '/system/bin/firewall-watcher --test-notify com.example.test'
   ```
2. Or use helper scripts (push from repo):
   - `scripts/test-firewall-notify.sh <package>`
   - `scripts/diagnose-firewall-notify.sh`
3. In log, search for `notify: path=` or `ERROR: notify`.
4. Settings → Apps → **Firewall Notify** → ensure notifications allowed (Android 13+).
5. After module update, priv-app overlay may need a reboot; fallback `pm install` is logged if overlay missing.

**adb tip:** avoid piping complex `grep` through `adb shell` (adb splits on `|`). Run scripts on-device or use quoted `su -c '…'`.

## App blocked but I want to allow it

- Tap **Allow** on the notification (if shown), or  
- Settings → Apps → \<app\> → enable network / mobile data & Wi‑Fi, or  
- Root CLI:
  ```bash
  firewallctl clear com.example.app
  # or
  /system/bin/firewall-allow-app com.example.app
  ```

Allowing does **not** add the app to `allowlist.txt`. A **reinstall** can be
blocked again unless you add the package to the allowlist manually.

## Sideloaded app should never be auto-blocked

Add to `/data/adb/firewall_default_deny/allowlist.txt`:

```text
com.my.sideloaded.app
```

Trigger a reconcile (e.g. install another app) or reboot. See [STATE.md](STATE.md).

## Too many apps blocked at once

The watcher logs `SAFETY: N changes (limit …)` and skips blocking when a single
diff would block more than `FIREWALL_MASS_BLOCK_LIMIT` (default 10). This
protects against bad `pm` output. Check log context; fix underlying PM issues.

## Termux: `firewallctl` not found

Ensure `.deb` installed and use Magisk `su` for root:

```bash
which firewallctl
su -c 'firewallctl list-policies'
```

## Build works on CI but not locally

- `make magisk` and `make test` need **ANDROID_HOME** with `platforms;android-34`
  and build-tools (for FirewallNotify.apk).
- `make test-host` runs watcher/shellcheck/doc tests **without** the SDK.

## Legacy benchmark script

`scripts/install-detect-benchmark.sh` still references `known.txt`; the
**production watcher does not use that file**. For signal timing experiments,
prefer `scripts/install-detect-inotify.sh` or compare `watcher.log` timestamps.
