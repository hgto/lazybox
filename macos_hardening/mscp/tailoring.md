# Tailoring the mSCP baseline

The whole point of mSCP is **one ruleset, many frameworks**. You edit/select
rules once and the generators emit configuration profiles, a check/fix
compliance script, human guidance, and SCAP content — with every rule already
mapped to NIST 800-53 / 800-171, CIS Level 1 & 2 + CIS Controls v8, and DISA
STIG. You never hand-maintain per-framework lists.

## Where the knobs live (in `vendor/macos_security/`)

- `rules/` — the canonical rule library. One YAML file per rule. Each rule
  carries its `result`/check, `fix`, the `mobileconfig` payload (if any), and
  the cross-framework `references:` (800-53, cis, 800-171, disa_stig, …).
- `baselines/` — keyword-selectable rule *sets*. A baseline is just a curated
  list of rule ids tagged with a keyword (`cis_lvl1`, `cis_lvl2`,
  `800-53r5_high`, `800-171`, `stig`, `all_rules`, …). `generate_baseline.py -k
  <keyword>` emits a tailored `build/baselines/<keyword>.yaml`.
- `custom/` — your **override layer**. Drop a file with the *same relative path*
  as a stock `rules/` file (e.g. `custom/rules/os/os_firewall_enable.yaml`) and
  it shadows the upstream rule without editing vendor code. This is the
  upgrade-safe place for site-specific values (e.g. a different idle timeout)
  and is what keeps your customizations intact across mSCP updates.
- `includes.yaml` (in the tailored baseline) — controls which odv (organization
  defined value) inputs and which rule groups are folded in. Use it to set ODVs
  like password length or screensaver timeout, and to include/exclude sections.

## Exemptions

Two complementary mechanisms:

1. **Drop the rule from the baseline.** Edit the generated
   `build/baselines/<baseline>.yaml` (or supply your own baseline YAML) and
   remove rule ids you do not want audited or remediated.
2. **Runtime exemption.** The generated compliance script honors an exemptions
   list; an exempt rule is recorded in the audit plist with `exempt = 1` and is
   reported as SKIP (not FAIL) by `compliance.sh`. Use this when a control is
   accepted-risk on a given host rather than removed fleet-wide.

## Customizing values (ODVs) the safe way

Prefer editing **`custom/`** + the baseline's **`includes.yaml`** over editing
`rules/` directly. Then re-run `generate.sh`. Because the override layer is
separate from `vendor/`, a `git pull` of a new mSCP release will not clobber it.

## Regenerating on a new macOS release

mSCP is version-agnostic because it ships a **branch per OS release** (e.g.
`sequoia`, `sonoma`, `ventura`, and the `os-26`/Tahoe line). On upgrade:

1. Re-run **`./bootstrap.sh`** — it maps the new `macos_major` to the matching
   branch (see the `case` table in `bootstrap.sh`) and checks it out.
2. Re-apply your `custom/` overrides if needed (they live outside `vendor/`).
3. Re-run **`./generate.sh`** (set `BASELINE=` to taste) to regenerate profiles,
   compliance script, and SCAP for the new OS.
4. Re-run **`./compliance.sh`** to audit, then `sudo ./compliance.sh fix` to
   remediate.

That single regeneration step re-emits artifacts for *every* mapped framework
at once — change a rule and CIS, NIST, and STIG outputs all move together.
