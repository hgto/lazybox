#!/bin/bash
# macos_hardening/bin/verify.sh
#
# Aggregate state-assertion / audit. Runs every component's verify script and
# folds the results into a single pass/fail summary with a CI-friendly exit
# code (0 = all compliant, 1 = at least one drift/failure).
#
# Audit-only: this NEVER changes state. Run it as often as you like, on a
# schedule, or from CI. Some checks read root-only data, so run with sudo for
# complete results.
#
# Usage:  sudo ./bin/verify.sh
set -uo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${BIN_DIR}/.." && pwd)"
# shellcheck source=../lib/common.sh disable=SC1091
. "${ROOT}/lib/common.sh"

require_macos

run_verify() {
  local name="$1" script="$2"
  printf '\n%s---------- verify: %s ----------%s\n' "$C_BLU" "$name" "$C_RESET"
  if [ ! -f "$script" ]; then
    mark_skip "$name (missing: $script)"
    return 0
  fi
  if /bin/bash "$script"; then
    HARDENING_PASS=$((HARDENING_PASS + 1)); log_ok "$name: compliant"
  else
    HARDENING_FAIL=$((HARDENING_FAIL + 1)); log_err "$name: drift/failures detected"
  fi
  return 0
}

log_info "macOS $(macos_version) — auditing lazybox hardening state"

run_verify "autolock" "${ROOT}/autolock/verify.sh"
run_verify "profiles" "${ROOT}/profiles/verify-profiles.sh"

printf '\n'
log_info "For the comprehensive mSCP baseline audit:  sudo ${ROOT}/mscp/compliance.sh"
summary
exit $?
