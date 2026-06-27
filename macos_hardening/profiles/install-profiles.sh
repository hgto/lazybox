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

log_info "Installing lazybox configuration profiles from ${SCRIPT_DIR}"

found=0
for f in "${SCRIPT_DIR}"/*.mobileconfig; do
  # Guard against a literal no-match glob.
  [ -e "$f" ] || continue
  found=$((found + 1))
  name="$(basename "$f")"
  run_step "Install ${name}" /usr/bin/profiles install -type configuration -path "$f"
done

if [ "$found" -eq 0 ]; then
  log_warn "No *.mobileconfig files found in ${SCRIPT_DIR}"
fi

summary; exit $?
