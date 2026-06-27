#!/bin/bash
# mscp/generate.sh
#
# Drive the mSCP generators to turn ONE tailored YAML baseline into the full
# set of hardening artifacts, then collect the ones we care about into
# mscp/build/ (gitignored).
#
# The mSCP value proposition: a single ruleset (rules/*.yaml + a baseline that
# selects a subset) generates configuration profiles, a check/fix compliance
# script, human guidance, and SCAP content -- and every rule is pre-mapped to
# NIST 800-53/800-171, CIS L1/L2 + CIS Controls v8, and DISA STIG. We just pick
# a baseline and run the generators.
#
# Pipeline:
#   1. generate_baseline.py -k <baseline>   -> build/baselines/<baseline>.yaml
#   2. generate_guidance.py -p -s -x <yaml> -> .mobileconfig profiles,
#                                              *_compliance.sh, and SCAP XML
#
# SAFETY: state-changing (writes files, runs the generators). Resilient: no
# `set -e`; every step wrapped in run_step. End `summary; exit $?`. We only
# WRITE this script -- do not execute it on a production Mac unprompted.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/../lib/common.sh"

require_macos

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
# Which baseline to tailor to. mSCP ships keywords like:
#   cis_lvl1, cis_lvl2, 800-53r5_high, 800-171, stig, all_rules ...
# Override with:  BASELINE=cis_lvl2 ./generate.sh
BASELINE="${BASELINE:-cis_lvl1}"

MSCP_DIR="${SCRIPT_DIR}/vendor/macos_security"
VENV_DIR="${MSCP_DIR}/.venv"
PY="${VENV_DIR}/bin/python3"
BUILD_DIR="${SCRIPT_DIR}/build"

# The generators must run with the repo as the working directory; they write
# relative to it (build/baselines, build/<baseline>/...). We collect outputs
# from there into our own build/ afterwards.
MSCP_BUILD="${MSCP_DIR}/build"
BASELINE_YAML="${MSCP_BUILD}/baselines/${BASELINE}.yaml"

log_info "Baseline: $BASELINE"

# Pre-flight: bootstrap must have run.
if [ ! -d "${MSCP_DIR}/.git" ]; then
  log_err "mSCP not present at ${MSCP_DIR}. Run ./bootstrap.sh first."
  summary; exit $?
fi
if [ ! -x "$PY" ]; then
  # Fall back to system python3 if the venv is missing; warn loudly.
  log_warn "venv python missing at $PY; falling back to /usr/bin/python3"
  PY="/usr/bin/python3"
fi

run_step "Create build directory" /bin/mkdir -p "$BUILD_DIR"

# ----------------------------------------------------------------------------
# Step 1: generate the tailored baseline YAML.
#   -k <keyword>  select rules tagged with this baseline keyword.
# Run with cwd = repo so relative output paths resolve.
# ----------------------------------------------------------------------------
run_step "generate_baseline.py -k ${BASELINE}" \
  /usr/bin/env -C "$MSCP_DIR" "$PY" ./scripts/generate_baseline.py -k "$BASELINE"

# ----------------------------------------------------------------------------
# Step 2: generate guidance + artifacts from that baseline YAML.
#   -p  emit configuration profiles (.mobileconfig)
#   -s  emit the check/fix compliance shell script (*_compliance.sh)
#   -x  emit SCAP content (XCCDF/OVAL XML)
# ----------------------------------------------------------------------------
if [ -f "$BASELINE_YAML" ]; then
  run_step "generate_guidance.py -p -s -x ${BASELINE}.yaml" \
    /usr/bin/env -C "$MSCP_DIR" "$PY" ./scripts/generate_guidance.py \
      -p -s -x "$BASELINE_YAML"
else
  log_err "Expected baseline YAML not found: $BASELINE_YAML"
  run_step_warn "Baseline YAML present" /bin/test -f "$BASELINE_YAML"
fi

# ----------------------------------------------------------------------------
# Step 3: collect the artifacts we consume (profiles + compliance script) into
# mscp/build/. The generators place per-baseline output under
# build/<baseline>/{mobileconfigs,...} and build/<baseline>/<baseline>_compliance.sh.
# We copy defensively across the likely layouts.
# ----------------------------------------------------------------------------
OUT_BASELINE_DIR="${MSCP_BUILD}/${BASELINE}"

collect() {
  # collect <description> <glob...>  -- copy matching files into build/.
  local desc="$1"; shift
  local found=0 f
  for f in "$@"; do
    if [ -e "$f" ]; then
      /bin/cp -f "$f" "${BUILD_DIR}/" 2>/dev/null && found=1
    fi
  done
  if [ "$found" -eq 1 ]; then
    HARDENING_PASS=$((HARDENING_PASS + 1)); log_ok "$desc"
  else
    HARDENING_WARN=$((HARDENING_WARN + 1)); log_warn "$desc (nothing matched)"
  fi
  return 0
}

# .mobileconfig configuration profiles
collect "Collect .mobileconfig profiles" \
  "${OUT_BASELINE_DIR}"/mobileconfigs/unsigned/*.mobileconfig \
  "${OUT_BASELINE_DIR}"/mobileconfigs/*.mobileconfig \
  "${OUT_BASELINE_DIR}"/preferences/*.mobileconfig \
  "${MSCP_BUILD}"/*.mobileconfig

# the *_compliance.sh check/fix script
collect "Collect compliance script" \
  "${OUT_BASELINE_DIR}"/*_compliance.sh \
  "${MSCP_BUILD}"/*_compliance.sh

# SCAP content (kept in repo build/, noted for the auditor)
if [ -d "${MSCP_BUILD}" ]; then
  log_dim "SCAP/XCCDF + guidance remain under: ${MSCP_BUILD}/${BASELINE}/"
fi

# Make any collected compliance script executable.
for f in "${BUILD_DIR}"/*_compliance.sh; do
  [ -e "$f" ] && /bin/chmod +x "$f" 2>/dev/null
done

log_info "Artifacts in: ${BUILD_DIR}"
log_info "Next: sudo ./compliance.sh         (audit / --check)"
log_info "      sudo ./compliance.sh fix     (remediate / --fix)"
summary; exit $?
