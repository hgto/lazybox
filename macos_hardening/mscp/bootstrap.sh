#!/bin/bash
# mscp/bootstrap.sh
#
# Clone the NIST macOS Security Compliance Project (mSCP) and install the
# Python + Ruby toolchain its generators need.
#
# mSCP is the authoritative, version-agnostic source of hardened macOS
# baselines. It is "version-agnostic" because the project maintains a SEPARATE
# GIT BRANCH per macOS release (e.g. `sequoia`, `sonoma`, `monterey`, and an
# `os-26`/`tahoe` line for macOS 26). Each branch carries the rules, baselines,
# and templates curated for THAT OS. So the right thing to do on any given Mac
# is to check out the branch matching the host's macOS major version, and to
# re-bootstrap onto the new branch whenever the host is upgraded.
#
# SAFETY: this script performs network + state-changing operations (git clone,
# pip install, bundle install). It is resilient (no `set -e`); every step is
# wrapped in run_step so a single failure is logged and counted but never
# aborts the run. End with `summary; exit $?`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/../lib/common.sh"

require_macos

# ----------------------------------------------------------------------------
# Paths (kept inside mscp/, gitignored: see .gitignore)
# ----------------------------------------------------------------------------
MSCP_REPO_URL="https://github.com/usnistgov/macos_security"
VENDOR_DIR="${SCRIPT_DIR}/vendor"
MSCP_DIR="${VENDOR_DIR}/macos_security"
VENV_DIR="${MSCP_DIR}/.venv"

# ----------------------------------------------------------------------------
# OS major -> mSCP branch mapping.
#
# mSCP names its per-release branches after the macOS marketing name. We map
# the kernel/marketing major version reported by sw_vers to that branch and
# fall back to `main` (the development tip / latest supported) for anything we
# do not explicitly know about. Update this table as new OSes ship.
#
#   15 -> Sequoia        (macOS 15)
#   14 -> Sonoma         (macOS 14)
#   13 -> Ventura        (macOS 13)
#   12 -> Monterey       (macOS 12)
#   26 -> Tahoe          (macOS 26 / the "os-26" line)
# ----------------------------------------------------------------------------
mscp_branch_for_major() {
  case "$1" in
    26) echo "os-26" ;;       # macOS 26 "Tahoe"
    15) echo "sequoia" ;;
    14) echo "sonoma" ;;
    13) echo "ventura" ;;
    12) echo "monterey" ;;
    *)  echo "main" ;;        # unknown / newer than this table: use dev tip
  esac
}

MAJOR="$(macos_major)"
BRANCH="$(mscp_branch_for_major "$MAJOR")"
log_info "Host macOS major=$MAJOR  ->  mSCP branch '$BRANCH'"
log_info "macOS version: $(macos_version)"

# ----------------------------------------------------------------------------
# 1. Clone (or fetch) the repo and check out the OS-appropriate branch.
# ----------------------------------------------------------------------------
run_step "Create vendor directory" /bin/mkdir -p "$VENDOR_DIR"

if [ -d "${MSCP_DIR}/.git" ]; then
  # Already cloned: fetch and switch to the desired branch (idempotent).
  run_step "Fetch latest mSCP refs" \
    /usr/bin/git -C "$MSCP_DIR" fetch --tags origin
  run_step "Check out mSCP branch '$BRANCH'" \
    /usr/bin/git -C "$MSCP_DIR" checkout "$BRANCH"
  run_step "Fast-forward '$BRANCH'" \
    /usr/bin/git -C "$MSCP_DIR" pull --ff-only origin "$BRANCH"
else
  # Fresh clone of just the chosen branch (shallow to save bandwidth).
  run_step "Clone mSCP ($BRANCH)" \
    /usr/bin/git clone --branch "$BRANCH" --single-branch \
      "$MSCP_REPO_URL" "$MSCP_DIR"
fi

# ----------------------------------------------------------------------------
# 2. Python venv + generator dependencies.
#    The generate_*.py scripts depend on PyYAML, xlwt, etc. listed in the
#    repo's requirements.txt.
# ----------------------------------------------------------------------------
run_step "Create Python venv" \
  /usr/bin/python3 -m venv "$VENV_DIR"

if [ -f "${MSCP_DIR}/requirements.txt" ]; then
  run_step "Upgrade pip in venv" \
    "${VENV_DIR}/bin/pip" install --upgrade pip
  run_step "pip install -r requirements.txt" \
    "${VENV_DIR}/bin/pip" install -r "${MSCP_DIR}/requirements.txt"
else
  run_step_warn "Locate requirements.txt" /bin/test -f "${MSCP_DIR}/requirements.txt"
fi

# ----------------------------------------------------------------------------
# 3. Ruby gems for the guidance (AsciiDoc -> HTML/PDF) pipeline.
#    The repo ships a Gemfile (asciidoctor, asciidoctor-pdf, rouge ...).
#    We install into a repo-local bundle path so we never touch system gems.
# ----------------------------------------------------------------------------
if [ -f "${MSCP_DIR}/Gemfile" ]; then
  if command -v bundle >/dev/null 2>&1; then
    run_step "bundle config (local path)" \
      /usr/bin/env -C "$MSCP_DIR" bundle config set --local path "vendor/bundle"
    run_step "bundle install (guidance gems)" \
      /usr/bin/env -C "$MSCP_DIR" bundle install
  else
    mark_skip "bundler not found; install Ruby/bundler for guidance (asciidoctor) output"
  fi
else
  run_step_warn "Locate Gemfile" /bin/test -f "${MSCP_DIR}/Gemfile"
fi

log_info "Bootstrap complete. Next: ./generate.sh (BASELINE=cis_lvl1 by default)"
summary; exit $?
