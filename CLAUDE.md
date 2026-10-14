# CLAUDE.md — MacStats

A native macOS menu-bar system monitor (Swift): CPU, RAM, network throughput and CPU
temperature. Repo: `openhoangnc/mac-stats`. Default branch `main`.

> **Scope note.** This file currently documents **the release pipeline only** — it was created on
> 2026-08-29 when that pipeline changed, and nobody has audited the rest of the codebase into it
> yet. Treat the absence of a section as "not written down", not as "nothing to know". Add sections
> as you learn the repo; don't assume this is a complete constitution.

## Releasing — a push to `main` no longer builds or releases (2026-08-29)

`.github/workflows/release.yml` used to run on **every** push to `main`. It auto-bumps the latest
`v*` tag, builds the app, **pushes the new git tag, and publishes a public GitHub Release with the
zip attached** — so every push to `main` cut a release, on a `macos-latest` runner (billed at 10×
the Linux rate on private repos).

It is now gated on a commit marker:

| Trigger | Runs when |
|---|---|
| push to `main` | a commit message in the push contains **`[deploy-prod]`** |
| push to any other branch | a commit message contains **`[deploy]`** |
| push of a `v*` **tag** | **always** — ungated |
| `workflow_dispatch` | **always** — ungated (takes the `bump_type` input) |

```bash
git commit -m "fix: whatever it was [deploy-prod]"   # cut a release
gh workflow run release.yml --ref main               # or do it by hand
git push origin v1.4.0                               # or tag it explicitly
```

⚠️ **Tag pushes are ungated on purpose, and must stay that way.** A tag push carries an **empty
`commits` payload**, so there is no message to read a marker out of — gating `refs/tags/v*` would
make `git push --tags` silently do nothing. `startsWith(github.ref, 'refs/tags/')` short-circuits
ahead of the marker test for exactly this reason.

⚠️ **A skipped run is GREEN AND EMPTY.** An unmarked push still shows a run in the Actions tab; the
job is skipped by its `if:`, allocates no runner, and does not read as a skip until you open it.
**Never take a green Actions tab as "it released"** — check the Releases page. If a release "did
nothing", look at the job's `if:` before debugging the version calculation or the build.

The workflow's own tag push uses `secrets.GITHUB_TOKEN`, and GitHub does not re-trigger workflows
from that token — so the tag it creates does *not* start a second run. That was true before this
change too; it is noted here only so nobody "fixes" a recursion that does not exist.

**Why two different markers** rather than `[deploy]` everywhere: the sibling repos on this account
fast-forward `main` from `dev` with byte-identical commits, so a shared token re-fires production on
every promotion. The condition is kept identical across all eleven repos in `~/priv` so there is one
rule to remember. Full reasoning: `~/priv/shopify-order-printer/docs/implementation-log.md` D-208
and D-210.

## Temperature sensors — Apple Silicon SMC key suffixes (2026-10-14)

On Apple Silicon a stem with an `a`/`b`/`x`/`z` set (`Tp2a`, `Tp2b`, `Tp2x`, `Tp2z`) is **one
sensor, four views**, not four sensors. Measured on an M1 MacBook Air (macOS 26) against the named HID
thermal sensors and the PMU die sensors, idle and under full load:

| Suffix | Meaning | Used for |
|---|---|---|
| `a` | live reading — tracks HID `pACC/eACC MTR Temp Sensor<n>` within ~0.5°C | **average** |
| `x` | recent peak — 2–6°C above `a`, holds after load drops; tracks `PMU tdie` | **max (hottest)** |
| `b` / `z` | `a` / `x` **plus a fixed per-sensor offset** (9–16°C on P-cores, constant under load) | nothing |

⚠️ **Never put `b`/`z` back into the average.** Averaging all four read ~4.6°C high on the M1 — the
displayed "average" was really closer to the hottest core. A stem *without* both `a` and `x` (e.g. M1
Pro's standalone `Tp0b`) is a plain reading and feeds both. Battery cells are `TB0T`/`TB1T`/`TB2T`
(match HID `gas gauge battery`); absent on desktops.

To re-verify on another chip: enumerate SMC keys via `#KEY` + `readIndex`, and read the HID sensors
(`IOHIDEventSystemClient`, usage page `0xff00` / usage `5`, event type 15) side by side while running
`yes > /dev/null` on every core — the suffix offsets are constant, so two samples show them.

## Auto-update — the release asset is a contract with every installed copy (2026-10-14)

`Updater.swift` polls `api.github.com/repos/openhoangnc/mac-stats/releases/latest` once a day,
downloads the asset named **`MacStats.zip`**, checks it (GitHub's `sha256` asset digest, bundle ID,
`CFBundleShortVersionString` == tag minus `v`, `LSMinimumSystemVersion`, `codesign --verify --deep
--strict`), swaps the whole bundle with `replaceItemAt` and relaunches. Installed copies hard-code
that contract, so changing any of these in `release.yml` silently strands every user on their
current version: the asset name, a top-level `MacStats.app/` inside the zip, `vX.Y.Z` tags, or the
version stamp.

⚠️ **`0.0.0` in `Info.plist` means "local build" and is load-bearing.** Local builds never check
on their own (only via "Check for Updates…"), so `./install.sh` from a checkout isn't overwritten
by the latest release a day later. CI stamps the real version with PlistBuddy and **fails the job**
if the stamp didn't take — a release shipped as `0.0.0` would never auto-update again.

Several macOS accounts on one Mac share `/Applications/MacStats.app`. The updater only replaces a
bundle it can write and that still holds the version it's running; if another account already put
a newer release there, it just relaunches into it, and it never auto-installs over a local build
that someone else dropped in. Failures log to `log show --predicate 'subsystem == "com.openhoangnc.macstats"'`.

To test end-to-end without a new release: copy a build somewhere writable, set its
`CFBundleShortVersionString` below the latest release with PlistBuddy, re-sign ad-hoc
(`codesign --force --deep --sign -`), clear `defaults delete com.openhoangnc.macstats
lastUpdateCheck`, and `open -n` it — it checks 30s after launch, installs and relaunches.
