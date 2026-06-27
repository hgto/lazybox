#!/bin/bash
# macos_hardening/bin/harden.sh
#
# Orchestrator for the "quick start / no-MDM" hardening path. Applies the
# curated configuration profiles and the 1-minute autolock to THIS machine.
#
# Resilient by design: each component installer runs as a child process; if
# one fails we record it and continue to the next, then report an aggregate
# result. Re-running is safe (the installers are idempotent).
#
# For a managed fleet, do NOT run this on each laptop by hand — instead deliver
# the same profiles via MDM (see ../fleet) and use the comprehensive,
# auditable baseline from ../mscp. This script is the standalone path.
#
# Usage:  sudo ./bin/harden.sh
set -uo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${BIN_DIR}/.." && pwd)"
# shellcheck source=../lib/common.sh disable=SC1091
. "${ROOT}/lib/common.sh"

require_macos
require_root

# run_component "Name" /path/to/installer.sh
# Runs the installer visibly (so its own per-step log is shown), then folds its
# exit code into our aggregate counters.
run_component() {
  local name="$1" script="$2"
  printf '\n%s========== %s ==========%s\n' "$C_BLU" "$name" "$C_RESET"
  if [ ! -f "$script" ]; then
    mark_skip "$name (missing: $script)"
    return 0
  fi
  if /bin/bash "$script"; then
    HARDENING_PASS=$((HARDENING_PASS + 1)); log_ok "$name applied"
  else
    HARDENING_FAIL=$((HARDENING_FAIL + 1)); log_err "$name reported failures (continuing)"
  fi
  return 0
}

log_info "macOS $(macos_version) — applying lazybox standalone hardening"

run_component "Core hardening profiles" "${ROOT}/profiles/install-profiles.sh"
run_component "1-minute autolock"       "${ROOT}/autolock/install.sh"

printf '\n'
log_info "Done. Verify with:  sudo ${ROOT}/bin/verify.sh"
summary
exit $?
