# Fleet GitOps overlay — continuous verification of macOS hardening

This directory deploys the lazybox macOS hardening **configuration profiles** and
then **continuously verifies** device state with **osquery**, using
[Fleet](https://fleetdm.com) (fleetdm) driven entirely from version-controlled
YAML (GitOps).

It is a thin overlay: it does **not** redefine the hardening controls. It reuses
the exact `.mobileconfig` profiles produced by the sibling components and adds
(a) MDM delivery of those profiles to a team of MacBooks and (b) osquery
policies that independently check the same controls are actually in effect.

---

## What Fleet is, and why we chose it

Fleet is an open, **source-available** device-management and observability
platform built on **osquery** (the same osquery Facebook open-sourced). It can be
**self-hosted** (you run the server, the database, and hold the data).

For a "must not degrade security" baseline that matters:

- **Source-available, self-hostable.** We can read the code and run the whole
  stack ourselves — no opaque agent phoning a vendor cloud, no third party
  holding our fleet inventory. This is the core reason we use Fleet over
  proprietary MDMs like Jamf.
- **osquery-based verification.** Every check is just SQL against osquery's
  virtual tables, so "is FileVault on?" is answered by the device itself, not
  inferred from "we sent a profile once."
- **GitOps.** The desired state is YAML in this repo. Changes go through PR
  review and are applied by CI; the Fleet web UI is used **read-only** for
  dashboards. (This GitOps + read-only-UI model is described in Fleet's own docs;
  see "Where these claims come from" below.)

---

## Repository layout

```
fleet/
├── default.yml                       # global org_settings, controls, queries,
│                                     #   policies, agent_options, software
├── teams/
│   └── workstations.yml              # "Workstations" team: profile delivery,
│                                     #   policies, agent_options, enroll secret
├── lib/
│   ├── policies-macos.yml            # osquery PASS/FAIL hardening policies
│   └── queries-macos.yml             # saved queries for live reporting
├── .github/workflows/
│   └── fleet-gitops.yml              # CI: dry-run on PR, apply on push to main
└── README.md
```

Profiles themselves live in sibling components at the project root, and are
referenced by relative `path:` from `teams/workstations.yml`. Because `fleetctl`
resolves `path:` relative to the *file that contains it*, these use `../../`:

- `../../autolock/com.lazybox.autolock.mobileconfig` (1-minute autolock)
- `../../profiles/com.lazybox.filevault.mobileconfig` (FileVault)
- `../../profiles/com.lazybox.firewall.mobileconfig` (application firewall)

---

## Standing up a Fleet server (out of band, one time)

GitOps configures an *already running* Fleet server; it does not provision one.
Per Fleet's deployment docs, a server needs:

1. **MySQL** (primary datastore) and **Redis** (live-query pub/sub + caching).
2. **The Fleet server** itself, e.g.:
   - **Docker / Docker Compose** for a quick single-node setup, or
   - **Helm / Kubernetes** for production, or the official Terraform modules.
3. **Apple MDM enablement** (one time, done in the UI or with `fleetctl`):
   push an **APNs** certificate and connect **Apple Business Manager (ABM)** for
   automated enrollment. These credentials are NOT stored in GitOps.
4. **A `fleetd` agent package** built for your server and enroll secret:

   ```sh
   fleetctl package --type=pkg \
     --fleet-url=https://fleet.example.com \
     --enroll-secret=<Workstations team enroll secret>
   ```

   Install that `.pkg` on each MacBook (or deploy it via ABM/Automated Device
   Enrollment). `fleetd` bundles **Orbit** (updater/supervisor), **osquery** (the
   agent), and **Fleet Desktop** (menu-bar UI). On first check-in the host
   enrolls into the **Workstations** team (because the enroll secret maps it
   there) and starts answering the policies in `lib/policies-macos.yml`.

> Do not run any of the commands above from this repo's automation against a real
> Mac without intent — this overlay is YAML + CI only.

---

## The GitOps workflow

1. **Edit YAML** in this directory and open a pull request.
2. CI runs `fleetctl gitops --dry-run` (see `.github/workflows/fleet-gitops.yml`)
   to validate the change and show the diff without touching the server.
3. **Merge to `main`.** CI runs `fleetctl gitops` for real, which reconciles the
   Fleet server to match this repo: teams, controls (profiles), policies,
   queries, and agent options.
4. Operators use the **Fleet web UI read-only** for dashboards and live queries;
   all *changes* flow through this repo so the YAML stays the source of truth.

Secrets (`FLEET_URL`, `FLEET_API_TOKEN`, and the enroll secrets) are GitHub
repository secrets injected into the runner; the `$VAR` references in the YAML
are expanded by `fleetctl gitops` at apply time and never committed.

---

## How Fleet *independently verifies* a profile is installed

This is the property that makes the overlay worth having. With most MDMs,
"installed" means "the server sent a command and got an ack." Fleet goes further:

- After delivering a configuration profile, Fleet has the **osquery** agent on
  the device report what profiles are actually present. Fleet only marks a
  profile **"Verified"** once the device confirms it is installed; until then it
  shows **"Verifying,"** and if the profile is missing or was removed Fleet marks
  it **"Failed"** and **re-delivers** it. (This verify/redeliver behavior is
  documented by Fleet; see below.)
- We reinforce this with explicit policies in `lib/policies-macos.yml` that query
  the `macos_profiles` table by payload identifier (e.g.
  `com.lazybox.autolock`), plus *runtime* policies that check the control is
  truly active (`disk_encryption.encrypted`, `alf.global_state`,
  `screenlock.grace_period`, …) rather than merely "a profile exists." A profile
  can be present yet a setting overridden, so we check both the profile and the
  effect.

### The verification policies (and the osquery tables they use)

| Control | osquery table | Compliant when |
|---|---|---|
| Screen lock requires password | `screenlock` | `enabled = 1` |
| Screen lock grace period immediate | `screenlock` | `grace_period <= 60` |
| Screensaver idle ≤ 60s | `managed_policies` | `com.apple.screensaver` / `idleTime` ≤ 60 |
| FileVault enabled | `disk_encryption` | `encrypted = 1` |
| Application firewall enabled | `alf` | `global_state >= 1` |
| Gatekeeper enabled | `gatekeeper` | `assessments_enabled = 1` |
| Automatic updates enabled | `managed_policies` | `com.apple.SoftwareUpdate` / `AutomaticCheckEnabled = 1` |
| Autolock / FileVault / firewall profile installed | `macos_profiles` | matching `identifier` present |

Each policy query is written so a **compliant** device returns **≥ 1 row** (Fleet
treats ≥ 1 row as *pass*, 0 rows as *fail*).

---

## Premium caveat

Some capabilities require **Fleet Premium** (paid tier) and/or the `fleetd`
agent rather than plain osquery:

- The **prebuilt CIS benchmark policy library** for macOS ships with Fleet
  Premium. The policies in this overlay are hand-written equivalents for the
  specific lazybox controls, so they run on the free tier — but if you want the
  full CIS Level 1/2 packs, that is a Premium feature.
- Several **MDM / teams features** (e.g. multiple teams, scripts, some OS-update
  enforcement, disk-encryption key escrow) depend on Fleet Premium and on hosts
  running **`fleetd`** (Fleet's osquery distribution) rather than vanilla
  osquery. Plain-osquery hosts can still answer queries but won't get the MDM and
  Orbit features.

Check current tier boundaries against Fleet's pricing/docs before relying on a
specific feature.

---

## Where these claims come from

Statements about Fleet's behavior — being source-available and self-hostable,
the GitOps + read-only-UI model, the profile **verify/redeliver** lifecycle, the
osquery table schema, and which features are **Premium** — rest on Fleet's own
documentation:

- YAML / GitOps schema: <https://fleetdm.com/docs/configuration/yaml-files>
- GitOps template this layout mirrors: <https://github.com/fleetdm/fleet-gitops>
- osquery table schema (table/column names used above):
  <https://fleetdm.com/tables>
- Configuration profile status & verification: Fleet MDM docs under
  <https://fleetdm.com/docs>

These should be re-checked against the version of Fleet you actually deploy, as
schema and tiering can change between releases.
