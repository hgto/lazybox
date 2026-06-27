# macos_hardening

Repeatable, idempotent, version-agnostic hardening for a fleet of MacBooks —
with continuous **state assertion** and a resilient "keep going even if one
command fails" design. Includes a concrete **1-minute autolock**.

This is deliberately a **layered** toolkit, not a single script, because modern
macOS has moved the security-critical settings *out* of reach of ad-hoc
`defaults write` and into **configuration profiles**. The layers:

| Layer | Directory | Role |
|-------|-----------|------|
| **Baseline source of truth** | [`mscp/`](mscp/) | NIST [macOS Security Compliance Project](https://github.com/usnistgov/macos_security). One YAML ruleset → profiles + check/fix compliance scripts + SCAP, mapped to NIST 800-53/800-171, **CIS L1&L2**, and DISA STIG. Continuously curated per macOS release → *version-agnostic*. |
| **Enforcement (curated subset)** | [`profiles/`](profiles/) | Hand-curated `.mobileconfig` profiles for the core controls (FileVault, firewall, Gatekeeper, auto-updates, loginwindow). Installable standalone *or* via MDM. |
| **The headline control** | [`autolock/`](autolock/) | **Screen lock after 1 minute, password required immediately.** Profile (authoritative) + a belt-and-suspenders idle watchdog for unmanaged devices. |
| **Remote management + continuous verify** | [`fleet/`](fleet/) | [Fleet](https://github.com/fleetdm/fleet) GitOps overlay: deploy the same profiles and *continuously verify actual device state* via osquery. Self-hosted / source-available, so remote management doesn't degrade security. |
| **Resilient foundation** | [`lib/common.sh`](lib/common.sh) | Shared bash 3.2 library: `run_step` (never aborts on failure), `assert_*` (audit without mutating), pass/fail counters, CI-friendly exit codes. |
| **Orchestration** | [`bin/`](bin/) | `harden.sh` (apply) and `verify.sh` (audit) tie the standalone path together. |

## How this meets the requirements

- **Repeatable / idempotent** — profiles are declarative; installers re-check
  state before changing it; re-running is safe.
- **Version-agnostic** — `mscp/bootstrap.sh` checks out the mSCP branch for the
  host's macOS major version; profiles use Apple's stable payload keys.
- **Runs anywhere** — pure `/bin/bash` 3.2, no dependencies for the standalone
  path. Works with or without an MDM.
- **Asserts state** — every component has a `verify*.sh` that compares actual
  vs expected and emits a pass/fail; `bin/verify.sh` aggregates them; Fleet does
  it continuously via osquery; mSCP compliance scripts write an audit plist.
- **Resilient** — nothing uses `set -e`. `run_step` logs a failure, counts it,
  and continues. A nonzero *summary* exit code still surfaces to CI.
- **Remote mgmt without degrading security** — Fleet is self-hostable and
  source-available (auditable), unlike proprietary Jamf.

## Quick start (standalone, no MDM)

```bash
# Apply curated profiles + 1-minute autolock to this Mac
sudo ./bin/harden.sh

# Audit state at any time (audit-only, never mutates)
sudo ./bin/verify.sh
```

> ⚠️ These scripts change system security settings and install configuration
> profiles + a LaunchAgent. Review them first. On a managed fleet, deliver the
> profiles via MDM instead of running `harden.sh` on each laptop by hand.

## Recommended path for a real fleet

1. **Baseline** — `cd mscp && ./bootstrap.sh && ./generate.sh` to produce the
   full CIS-aligned profiles + compliance scripts from NIST's source of truth.
   Re-run after each macOS release (it switches branches automatically).
2. **Enforce** — deliver the profiles (from `mscp/build/`, plus the curated
   `profiles/` and `autolock/` ones) through an MDM.
3. **Manage + verify remotely** — stand up **Fleet** ([`fleet/`](fleet/)),
   enroll the Macs, and drive everything via GitOps. Fleet independently
   confirms via osquery that each profile is *actually installed* (not just
   acknowledged) and continuously checks the verification policies.
4. **Audit** — `bin/verify.sh` and `mscp/compliance.sh --check` for on-device
   audit; Fleet policies for fleet-wide reporting.

## The 1-minute autolock, specifically

Two parts, because macOS requires it:

- **Password-on-wake** (`askForPassword` / `askForPasswordDelay=0`) **must** be
  a configuration profile — the legacy `defaults write com.apple.screensaver`
  path stopped working reliably as of macOS Sonoma. See
  [`autolock/com.lazybox.autolock.mobileconfig`](autolock/com.lazybox.autolock.mobileconfig)
  (`idleTime=60`, `askForPassword=1`, `askForPasswordDelay=0`).
- **Idle-triggered locking** is enforced by the profile's screensaver timeout,
  with [`autolock/idle-lock.sh`](autolock/idle-lock.sh) (a LaunchAgent watchdog
  reading `HIDIdleTime` via `ioreg`) as defense-in-depth for unmanaged devices.

See [`autolock/README.md`](autolock/README.md) for the full rationale.

## Validation status

All shell scripts pass `bash -n` + `shellcheck`; all `.mobileconfig`/`.plist`
files pass `plutil -lint`. Nothing in this repo was executed against a live
machine during development — the installers are written and statically
validated only. **Test on a spare/lab Mac before fleet rollout.**

## Caveats worth knowing

- macOS hardening is version-sensitive; **regenerate the mSCP baseline per OS
  release** and re-test the autolock payload keys on new majors.
- Fleet's prebuilt CIS benchmark *policies* and some MDM features require the
  paid **Premium** tier and the `fleetd` agent; the osquery verification
  policies here are plain and work on the free tier.
- Some osquery table/column names in `fleet/lib/policies-macos.yml` should be
  re-checked against your deployed Fleet/osquery version.
- FileVault key **escrow** requires an MDM; the standalone FileVault profile
  enables encryption but cannot escrow the recovery key.
