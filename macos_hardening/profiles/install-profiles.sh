#!/bin/bash
# macos_hardening/profiles/install-profiles.sh
#
# Stage the lazybox COMBINED configuration profile for approval.
#
# macOS 26 removed `profiles install` from the CLI, and only ONE downloaded
# profile can be pending review at a time -- so we ship every payload in a
# single profile (com.lazybox.hardening.mobileconfig) and `open` it once. A
# single approval in System Settings then applies the whole baseline.
#
# NOTE: On a managed fleet you should NOT run this. Deliver the individual
# per-control profiles via your MDM instead -- MDM delivery is supervised,
# survives reinstalls, enables recovery-key escrow for FileVault, and prevents
# users from removing the profiles. This script is for standalone / lab use.
#
# Resilient: a failing stage never aborts the run (run_step / stage_profile).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../lib/common.sh"

require_macos
require_root "$@"

COMBINED="${SCRIPT_DIR}/com.lazybox.hardening.mobileconfig"

log_info "Staging the lazybox combined hardening profile"
log_info "macOS no longer installs profiles from the CLI; it will open in System Settings for approval."

if [ ! -f "$COMBINED" ]; then
  log_err "Combined profile not found: $COMBINED"
  HARDENING_FAIL=$((HARDENING_FAIL + 1))
  summary; exit $?
fi

stage_profile "$COMBINED"

if [ "$HARDENING_SKIP" -eq 0 ]; then
  log_info "ACTION REQUIRED: open System Settings > General > VPN & Device Management"
  log_info "(or Privacy & Security > Profiles) and approve the staged profile within ~8 minutes."
fi

summary; exit $?
