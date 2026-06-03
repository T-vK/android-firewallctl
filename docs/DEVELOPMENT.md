# Development

Guide for contributors: testing, CI, git hooks, and release process.

**Building artifacts from source:** see [BUILD.md](BUILD.md).

## Tests

Tests are **host-side** shell scripts under `tests/`. There are **no**
emulator or on-device tests in CI by design.

| Command | What runs |
|---|---|
| `make test-host` | `test-watcher.sh`, `test-shellcheck.sh`, `test-docs.sh` — needs dex jar + deb only |
| `make test` | Full suite including `test-packaging.sh` (needs `make magisk` / Android SDK) |

```bash
make test-host    # quick, no ANDROID_HOME
make test         # same as GitHub Actions build-and-test job
```

Add checks by creating `tests/test-*.sh`; `tests/run-tests.sh` auto-discovers them.

### What is covered

- **Watcher logic** — stubbed `pm` / `firewallctl` / `am` / `cmd`; in-memory baseline, allowlist, reinstall, safety drops.
- **Packaging** — deb paths, Magisk zip entries, dex magic.
- **Shellcheck** — all repo shell scripts (with Android-specific exceptions documented in the test).
- **Documentation** — `tests/test-docs.sh` guards against stale terms (e.g. `known.txt` as production state).

### What is not covered

- Real Binder calls to NPMS on a device
- Notification UI on API 33+
- Magisk boot timing

Manual checks on the [reference stack](COMPATIBILITY.md) remain the source of truth for behavior.

## CI & releases

`.github/workflows/ci.yml` on push/PR to `main`:

1. Builds dex, deb, Magisk zip (with Android SDK).
2. Runs `make test`.
3. Uploads artifacts.

On push to `main`, **semantic-release** may tag and publish a GitHub Release with
version-stamped artifacts. Commit messages should follow
[Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, …).

Config: `.releaserc.json`.

## Diagnostic scripts (on device)

| Script | Purpose |
|---|---|
| `scripts/test-firewall-notify.sh` | Exercise notify pipeline for a package |
| `scripts/diagnose-firewall-notify.sh` | Dump APK / permission / dumpsys state |
| `scripts/install-detect-inotify.sh` | Log inotify events under `/data/system` |
| `scripts/install-detect-benchmark.sh` | Legacy timing helper (references obsolete `known.txt`) |

## Git hooks (required for contributors)

Cursor may install hooks under `~/.cursor/agent-hooks/` that append
`Co-authored-by:` lines. This repo does **not** use those.

After clone, run once:

```bash
./scripts/setup-git.sh
```

That removes the Cursor agent hooks for this workspace, sets your author
identity, and points `core.hooksPath` at `.githooks/` (strips any
`Co-authored-by` trailer from commit messages).

## Contributing

1. Do not change runtime behavior without maintainer sign-off — the stack is validated on a single device/ROM.
2. Prefer doc fixes and host tests for regressions in docs/packaging.
3. Use `feat:` / `fix:` (and other conventional types) in commit messages for releases.
4. Never add `Co-authored-by:` trailers to commits in this repository.

## License

Apache-2.0 — see [LICENSE](../LICENSE).
