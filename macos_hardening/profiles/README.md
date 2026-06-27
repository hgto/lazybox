# lazybox — Core Hardening Configuration Profiles

Standalone-installable macOS configuration profiles (`.mobileconfig`) that
enforce a set of CIS-aligned baseline controls, plus resilient install /
uninstall / verify scripts.

These profiles are **system-scope** and carry **hardcoded UUIDs and
PayloadIdentifiers**, so re-installs and MDM diffs stay stable.

> **Note on the autolock control:** screen-lock / password-on-wake is enforced
> by the separate `autolock/` component, not here. This component stays in its
> lane (FileVault, firewall, Gatekeeper, software update, login window).

## Profiles

| File | Payload type(s) | Control enforced |
| --- | --- | --- |
| `com.lazybox.filevault.mobileconfig` | `com.apple.MCX.FileVault2` | Full-disk encryption (FileVault 2), deferred to next login, personal recovery key |
| `com.lazybox.firewall.mobileconfig` | `com.apple.security.firewall` | Application firewall **on** + stealth mode; does not block all incoming |
| `com.lazybox.gatekeeper.mobileconfig` | `com.apple.systempolicy.control` | Gatekeeper assessment enforced; App Store + identified developers allowed |
| `com.lazybox.softwareupdate.mobileconfig` | `com.apple.SoftwareUpdate`, `com.apple.applicationaccess` | Automatic update check/download/install incl. security responses & config data; forced automatic date & time |
| `com.lazybox.loginwindow.mobileconfig` | `com.apple.loginwindow` | Guest account disabled, name+password login (no user list), console login disabled, no password hints |
| `com.lazybox.hardening.mobileconfig` | **all of the above + `com.apple.screensaver`** | **Combined** profile bundling every payload (incl. auto-lock). Staged by `install-profiles.sh` for the standalone path. |

> **macOS 26 note:** `profiles install` was removed from the CLI, and only one
> downloaded profile can be pending review at a time. The standalone installer
> therefore stages the single **combined** profile and you approve it once in
> **System Settings → General → VPN & Device Management** (within ~8 minutes).
> The individual per-control files above remain for granular MDM delivery.

### Control rationale (CIS / mSCP)

The settings map to the CIS Apple macOS Benchmark and the macOS Security
Compliance Project (mSCP) baseline:

- **FileVault** — CIS 2.6.x / mSCP `auth_pwpolicy`/`fdesetup` family. Full-disk
  encryption protects data at rest on lost or stolen devices.
  `Defer=true` avoids interrupting an active session; the user is prompted to
  enable FileVault at the next logout/login. `UseRecoveryKey=true` generates a
  personal recovery key.
- **Application Firewall** — CIS 2.2.x / mSCP `os_firewall_*`. Enabling the
  firewall and stealth mode reduces network attack surface and suppresses
  responses to unsolicited probes. `BlockAllIncoming=false` is deliberate so
  allowed signed services keep working.
- **Gatekeeper** — CIS 2.x / mSCP `os_gatekeeper_*`. Requiring assessment
  blocks unsigned/untrusted code. `AllowIdentifiedDevelopers=true` matches the
  default "App Store and identified developers" posture; set it to `false` in
  the profile for an "App Store only" lockdown.
- **Software Update** — CIS 1.x / mSCP `sysprefs_software_update_*`. Automatic
  checking, downloading, and installation (including security responses and
  XProtect/MRT/Gatekeeper config data) keeps systems patched. The bundled
  `com.apple.applicationaccess` payload forces automatic date & time so update
  scheduling and TLS validation remain correct.
- **Login Window** — CIS 2.x / mSCP `loginwindow_*`. Disabling the guest
  account, forcing name+password entry (no clickable user list), disabling
  console login, and suppressing password hints reduce credential exposure at
  the login window.

## FileVault recovery-key escrow caveat (IMPORTANT)

A **standalone** profile **cannot escrow** the FileVault personal recovery
key anywhere. Escrow requires an MDM-supplied
`com.apple.security.FDERecoveryKeyEscrow` payload (with the MDM's escrow URL
and certificate).

Consequences for standalone use:

- With `ShowRecoveryKey=false` (the default in this profile), the key is
  generated but **not displayed and not stored** — you can lose access to the
  data if the password is forgotten.
- For lab / standalone bootstrap, set `ShowRecoveryKey` to `true` in
  `com.lazybox.filevault.mobileconfig` so the key is shown once and an operator
  can record it securely.
- On a managed fleet, deliver FileVault via MDM with an escrow payload so keys
  are recoverable centrally.

## Deployment: MDM vs standalone

- **Managed fleet (recommended):** deliver every `.mobileconfig` through your
  MDM. MDM delivery is supervised, survives OS reinstall/enrollment, lets you
  escrow FileVault keys, and prevents users from removing the profiles.
- **Standalone / lab / bootstrap:** use `install-profiles.sh` (root required).
  Profiles installed this way are user-removable and cannot escrow keys.

## Scripts

All scripts source the shared resilient library at `../lib/common.sh`. None
use `set -e`; a single failing step is logged and counted but never aborts the
run. Each ends with a pass/fail/warn/skip `summary` and a CI-friendly exit
code (0 = clean).

### `install-profiles.sh` (root)

Loops over every `*.mobileconfig` in this directory and installs it:

```bash
sudo ./install-profiles.sh
```

> On a managed fleet, deliver via MDM instead of running this.

### `uninstall-profiles.sh` (root)

Removes each profile by `PayloadIdentifier`:

```bash
sudo ./uninstall-profiles.sh
```

> MDM-delivered profiles must be removed from the MDM, not with this script.

### `verify-profiles.sh` (audit only; run as root for full coverage)

Confirms each profile is installed and checks effective values where a
readable source of truth exists (`fdesetup status`, `socketfilterfw`,
`spctl --status`, and the managed `com.apple.SoftwareUpdate` /
`com.apple.loginwindow` preference domains):

```bash
sudo ./verify-profiles.sh
```

FileVault may report a warning (not a failure) until the user completes the
deferred enablement at their next logout/login.

## Validation

Every profile is validated with `plutil -lint`; every script with `bash -n`
and `shellcheck`. See the component summary for results.
