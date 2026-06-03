# Compatibility

## Verified environment

This project has **only** been exercised end-to-end on:

| | |
|---|---|
| **Device** | Google Pixel 4 |
| **ROM** | LineageOS 23 |
| **Root** | Magisk (module install + `su`) |
| **Use case** | Magisk default-deny module + `firewallctl` CLI + FirewallNotify |

Treat this as the **reference stack**. Bug reports are most useful when they
include the same details (ROM build date, Magisk version, module version).

## Requirements (theoretical)

These are design targets inferred from the code, **not** a guarantee on
untested devices:

| Requirement | Reason |
|---|---|
| **Root** | `app_process` must call `INetworkPolicyManager` as root. |
| **API 26+** | DEX built with `--min-api 26`; NPMS policy model assumed. |
| **AOSP-style NPMS** | Per-app “mobile data & Wi‑Fi” / `POLICY_REJECT_*` in Settings. |
| **`inotifyd`** | Magisk module install detection (toybox/busybox on device). |
| **Magisk** | For the shipped module zip overlay and `service.sh` boot hook. |

## Unsupported / unknown

The maintainers **do not** currently support or test:

- Stock Google Pixel / Samsung / other OEM ROMs without root
- LineageOS 20/21/22 or Android versions other than what ships on LOS 23 for Pixel 4
- Kernels or ROMs without standard NPMS / Settings network toggles
- Non-Magisk root (KernelSU-only, etc.) — may work, not validated
- Emulators or CI device farms (no automated on-device tests in this repo)

If something works elsewhere, that is helpful community knowledge, not an
official compatibility promise.

## CLI without the Magisk module

`firewallctl` alone only needs:

- Root shell
- Working `netpolicy` Binder service
- Readable `/data/system/packages.list` for package→UID resolution

The Magisk module adds install watching, notifications, and priv-app overlay —
those parts are **more** ROM-sensitive than the bare CLI.

## Policy flag names

ROMs expose different `POLICY_*` constants. Always run on **your** device:

```bash
firewallctl list-policies
```

Lineage/AOSP names like `REJECT_ALL` are typical; your build may differ.

## Reporting issues

Include:

1. Device model  
2. Exact ROM name and build id  
3. Magisk version  
4. Module / release version (`module.prop` or GitHub tag)  
5. Relevant excerpt of `/data/adb/firewall_default_deny/watcher.log`
