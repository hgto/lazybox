# mscp — NIST macOS Security Compliance Project integration

This component wires the fleet-hardening toolkit to the **macOS Security
Compliance Project (mSCP)**, the authoritative source of hardened macOS
baselines.

## What mSCP is

[mSCP](https://github.com/usnistgov/macos_security) is an open-source project
**hosted by NIST** (`usnistgov`) and maintained collaboratively across multiple
U.S. federal agencies (NIST, NASA, DISA, the Los Alamos National Laboratory,
and others). It is the de-facto reference for "how do I securely configure this
version of macOS," and it underpins published CIS Benchmarks and DISA STIGs for
macOS.

Crucially, mSCP is **one ruleset that maps to many frameworks at once**. Each
rule in `rules/` carries cross-references to:

- **NIST SP 800-53** (rev 5) and **NIST SP 800-171**
- **CIS** Level 1 & Level 2, plus **CIS Controls v8**
- **DISA STIG**

Pick a baseline keyword and the generators emit everything mapped to those
frameworks simultaneously. You never maintain per-framework spreadsheets.

## Why it's the source of truth here

The toolkit also ships a small set of **hand-crafted profiles** in
[`../profiles`](../profiles) and [`../autolock`](../autolock) (FileVault, a
1-minute autolock, an idle-lock watchdog). Those are a deliberately tiny,
**curated subset for the no-MDM quick start** — drop-in `.mobileconfig`/scripts
you can apply on a single Mac in minutes without standing up infrastructure.

mSCP is the other end of the spectrum: the **comprehensive, auditable,
continuously-curated baseline**. When you want the full, defensible, mapped-to-
frameworks posture (and the ability to *prove* it), you generate from mSCP. The
quick-start profiles are intentionally a strict subset of what an mSCP baseline
like `cis_lvl1` produces, so adopting mSCP later is additive, not a rewrite.

## Why it's version-agnostic

mSCP maintains a **separate git branch per macOS release** (`sequoia`,
`sonoma`, `ventura`, the `os-26`/Tahoe line, …). Each branch is continuously
curated for the rules, payload keys, and baselines valid on *that* OS. So the
correct artifacts for any given Mac come from checking out the branch matching
its macOS major version — and a new OS just means re-running bootstrap on the
new branch. `bootstrap.sh` encodes that OS→branch mapping (`case "$(macos_major)"`)
and falls back to `main` for anything newer than its table.

## The pipeline

```
bootstrap.sh   clone mSCP @ OS-appropriate branch + set up Python venv / Ruby gems
      │
      ▼
generate.sh    generate_baseline.py -k <BASELINE>      → tailored baseline YAML
               generate_guidance.py -p -s -x <yaml>    → profiles + compliance script + SCAP
                 -p  configuration profiles (.mobileconfig)
                 -s  check/fix compliance shell script (*_compliance.sh)
                 -x  SCAP content (XCCDF / OVAL XML)
               …then copies .mobileconfig + *_compliance.sh into build/
      │
      ▼
compliance.sh  ./compliance.sh           → runs *_compliance.sh --check (audit)
               sudo ./compliance.sh fix   → runs *_compliance.sh --fix  (remediate)
               then reads /Library/Preferences/org.<baseline>.audit.plist
               and prints a per-rule pass/fail summary
```

## Quick start

```bash
cd mscp

# 1. Clone mSCP for this Mac's OS + install the generator toolchain.
./bootstrap.sh

# 2. Generate artifacts for a baseline (default: cis_lvl1).
BASELINE=cis_lvl1 ./generate.sh        # or cis_lvl2, 800-53r5_high, stig, …

# 3. Audit (read-only), then remediate.
sudo ./compliance.sh                   # --check, summarizes the audit plist
sudo ./compliance.sh fix               # --fix (root required)
```

### The check/fix audit-plist verification flow

The generated `*_compliance.sh` writes its results to
`/Library/Preferences/org.<baseline>.audit.plist`. Each top-level key is a rule
id whose dict has a `finding` boolean — **`finding = true` means
NON-compliant** — and an `exempt` flag. `compliance.sh` runs the script in
`--check` mode, then reads that plist back (`plutil -p` for the raw dump, then
`defaults read` per rule) and reports each rule as pass / fail / skip(exempt),
feeding the shared pass/fail counters so the exit code is CI-meaningful.

## Files

| File            | Purpose |
|-----------------|---------|
| `bootstrap.sh`  | Clone mSCP @ OS-appropriate branch; set up venv + Ruby gems. |
| `generate.sh`   | Run the generators; collect profiles + compliance script into `build/`. |
| `compliance.sh` | Run the compliance script (`--check`/`--fix`); summarize the audit plist. |
| `tailoring.md`  | How to customize the baseline and regenerate on a new macOS release. |
| `.gitignore`    | Ignore `vendor/` (clone) and `build/` (generated). |

`vendor/` and `build/` are generated and gitignored; re-create them with
`bootstrap.sh` and `generate.sh`.
