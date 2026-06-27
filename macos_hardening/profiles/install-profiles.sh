#!/bin/bash
# macos_hardening/profiles/install-profiles.sh
#
# Install every lazybox *.mobileconfig in this directory as a system-scope
# configuration profile.
#
# NOTE: On a managed fleet you should NOT run this. Deliver these profiles
# via your MDM instead -- MDM delivery is supervised, survives reinstalls,
# enables recovery-key escrow for FileVault, and prevents users from removing
# the profiles. This script exists for standalone / lab / bootstrap use.
#
# Resilient: a single failing install never aborts the run (run_step).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../lib/common.sh"

require_macos
require_root "$@"

log_info "Staging lazybox configuration profiles from ${SCRIPT_DIR}"
log_info "macOS no longer installs profiles from the CLI; each will open in System Settings for approval."

found=0
for f in "${SCRIPT_DIR}"/*.mobileconfig; do
  # Guard against a literal no-match glob.
  [ -e "$f" ] || continue
  found=$((found + 1))
  stage_profile "$f"
done

if [ "$found" -eq 0 ]; then
  log_warn "No *.mobileconfig files found in ${SCRIPT_DIR}"
elif [ "$HARDENING_SKIP" -eq 0 ]; then
  log_info "ACTION REQUIRED: open System Settings > General > VPN & Device Management"
  log_info "(or Privacy & Security > Profiles) and approve each staged profile within ~8 minutes."
fi

summary; exit $?
