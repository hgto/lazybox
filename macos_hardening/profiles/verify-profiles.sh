#!/bin/bash
# macos_hardening/profiles/verify-profiles.sh
#
# AUDIT ONLY. Confirms each lazybox profile is installed and, where feasible,
# that its effective on-disk values match. Never mutates anything.
#
# Run as root for the most complete view (some managed domains and the
# firewall/FileVault state require root to read).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${SCRIPT_DIR}/../lib/common.sh"

require_macos

log_info "Verifying lazybox configuration profiles (audit only)"

# ---------------------------------------------------------------------------
# 1. Each profile is installed (by top-level PayloadIdentifier).
# ---------------------------------------------------------------------------
assert_profile_installed "com.lazybox.filevault"
assert_profile_installed "com.lazybox.firewall"
assert_profile_installed "com.lazybox.gatekeeper"
assert_profile_installed "com.lazybox.softwareupdate"
assert_profile_installed "com.lazybox.loginwindow"

# ---------------------------------------------------------------------------
# 2. Effective values, where there is a readable source of truth.
# ---------------------------------------------------------------------------

# FileVault: actual encryption status (Defer means this may still be "Off"
# until the user logs out/in, so this is a warn-level best-effort check).
fv_status="$(/usr/bin/fdesetup status 2>/dev/null)"
case "$fv_status" in
  *"FileVault is On"*)
    HARDENING_PASS=$((HARDENING_PASS + 1)); log_ok "FileVault is On" ;;
  *)
    HARDENING_WARN=$((HARDENING_WARN + 1))
    log_warn "FileVault not yet On (Defer enables it at next logout): ${fv_status:-unknown}" ;;
esac

# Firewall: socketfilterfw global state (root recommended).
# socketfilterfw uses different vocabularies per query: --getglobalstate says
# "enabled"/"disabled" while --getstealthmode says "is on"/"is off". Match both.
fw_global="$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)"
case "$fw_global" in
  *"enabled"*|*"is on"*) HARDENING_PASS=$((HARDENING_PASS + 1)); log_ok "Application firewall enabled" ;;
  "")                    mark_skip "Firewall state unreadable (run as root?)" ;;
  *)                     HARDENING_FAIL=$((HARDENING_FAIL + 1)); log_err "Application firewall NOT enabled: $fw_global" ;;
esac

fw_stealth="$(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null)"
case "$fw_stealth" in
  *"enabled"*|*"is on"*) HARDENING_PASS=$((HARDENING_PASS + 1)); log_ok "Firewall stealth mode enabled" ;;
  "")                    mark_skip "Stealth mode unreadable (run as root?)" ;;
  *)                     HARDENING_FAIL=$((HARDENING_FAIL + 1)); log_err "Firewall stealth mode NOT enabled: $fw_stealth" ;;
esac

# Gatekeeper: spctl assessment status.
gk_status="$(/usr/sbin/spctl --status 2>/dev/null)"
case "$gk_status" in
  *"assessments enabled"*) HARDENING_PASS=$((HARDENING_PASS + 1)); log_ok "Gatekeeper assessments enabled" ;;
  "")                      mark_skip "Gatekeeper status unreadable" ;;
  *)                       HARDENING_FAIL=$((HARDENING_FAIL + 1)); log_err "Gatekeeper NOT enabled: $gk_status" ;;
esac

# Software update: read the EFFECTIVE value (managed preferences win over the
# local domain — a configuration profile writes to /Library/Managed Preferences).
assert_effective "SoftwareUpdate AutomaticCheckEnabled" \
  com.apple.SoftwareUpdate AutomaticCheckEnabled 1
assert_effective "SoftwareUpdate AutomaticDownload" \
  com.apple.SoftwareUpdate AutomaticDownload 1
assert_effective "SoftwareUpdate CriticalUpdateInstall" \
  com.apple.SoftwareUpdate CriticalUpdateInstall 1
assert_effective "SoftwareUpdate ConfigDataInstall" \
  com.apple.SoftwareUpdate ConfigDataInstall 1

# Login window: guest account disabled + name/password login (managed-aware).
assert_effective "Loginwindow guest account disabled" \
  com.apple.loginwindow GuestEnabled 0
assert_effective "Loginwindow SHOWFULLNAME (name+password)" \
  com.apple.loginwindow SHOWFULLNAME 1

summary; exit $?
