#!/bin/bash
# macos_hardening/profiles/uninstall-profiles.sh
#
# Remove every lazybox configuration profile this component installs, by
# PayloadIdentifier. Resilient: a profile that is not present is reported as
# a failure for that step but never aborts the run.
#
# NOTE: MDM-delivered profiles cannot be removed with `profiles remove`;
# remove those from the MDM instead.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../lib/common.sh"

require_macos
require_root "$@"

# The top-level PayloadIdentifiers this component owns.
IDENTIFIERS="
com.lazybox.filevault
com.lazybox.firewall
com.lazybox.gatekeeper
com.lazybox.softwareupdate
com.lazybox.loginwindow
"

log_info "Removing lazybox configuration profiles"

for ident in $IDENTIFIERS; do
  [ -n "$ident" ] || continue
  run_step "Remove ${ident}" /usr/bin/profiles remove -identifier "$ident"
done

summary; exit $?
