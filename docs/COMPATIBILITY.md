# Compatibility

## What has been tested

End-to-end use (Magisk module, install blocking, notifications, CLI) has
**only** been tested on:

| | |
|---|---|
| **Device** | Google Pixel 4 |
| **ROM** | LineageOS 23 |
| **Root** | Magisk |

That is the stack the maintainer uses day to day. Bug reports are especially
helpful when they include ROM build id, Magisk version, and module version.

## Trying it on other setups

Nothing in the design is Pixel-4-specific on purpose. If your ROM exposes the
same per-app network toggles in Settings (AOSP / Lineage-style
`NetworkPolicyManager`) and you have root, it is reasonable to try the CLI or
the Magisk module. Please open an issue or PR with what worked or what broke —
that helps everyone.

## Likely requirements

| Requirement | Why |
|---|---|
| **Root** | `app_process` must call `INetworkPolicyManager` as root. |
| **API 26+** | DEX built with `--min-api 26`; NPMS policy model assumed. |
| **AOSP-style NPMS** | Per-app “mobile data & Wi‑Fi” / `POLICY_REJECT_*` in Settings. |
| **`inotifyd`** | Magisk module install detection (toybox/busybox on device). |
| **Magisk** | For the shipped module zip overlay and `service.sh` boot hook. |

Other root solutions (e.g. KernelSU) or ROMs have not been tested here yet.

## CLI without the Magisk module

`firewallctl` alone only needs:

- Root shell
- Working `netpolicy` Binder service
- Readable `/data/system/packages.list` for package→UID resolution

The Magisk module adds install watching, notifications, and priv-app overlay —
those paths are more ROM-sensitive than the bare CLI.

## Policy flag names

ROMs expose different `POLICY_*` constants. On your device, run:

```bash
firewallctl list-policies
```

Lineage/AOSP names like `REJECT_ALL` are typical; your build may differ.

## Reporting issues

Include:

1. Device model  
2. Exact ROM name and build id  
3. Root / Magisk version (or how you obtained root)  
4. Module / release version (`module.prop` or GitHub tag)  
5. Relevant excerpt of `/data/adb/firewall_default_deny/watcher.log`
