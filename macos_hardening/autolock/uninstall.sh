#!/bin/bash
# macos_hardening/autolock/uninstall.sh
#
# Resilient uninstaller: reverses everything install.sh did.
#   1. Bootout the LaunchAgent from the console user's GUI session.
#   2. Remove the LaunchAgent plist.
#   3. Remove the watchdog script (and installed lib copy).
#   4. Remove the configuration profile by identifier.
#
# Resilient: run_step everywhere, no `set -e`, ends with `summary; exit $?`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

require_macos
# shellcheck disable=SC2119  # require_root takes no args here
require_root

LIB_DIR="/usr/local/lib/lazybox"
WATCHDOG_DST="${LIB_DIR}/idle-lock.sh"
AGENT_DST="/Library/LaunchAgents/com.lazybox.idlelock.plist"
AGENT_LABEL="com.lazybox.idlelock"
PROFILE_IDENT="com.lazybox.autolock"

CONSOLE_USER="$(console_user)"

# ===========================================================================
# 1. Bootout the agent from the console user's GUI session.
# ===========================================================================
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
  mark_skip "No console GUI user; nothing to bootout from a session"
else
  CONSOLE_UID="$(/usr/bin/id -u "$CONSOLE_USER" 2>/dev/null)"
  if [ -n "$CONSOLE_UID" ]; then
    run_step_warn "Bootout agent from gui/${CONSOLE_UID}" \
      /bin/launchctl bootout "gui/${CONSOLE_UID}/${AGENT_LABEL}"
  else
    log_warn "Could not resolve uid for console user '$CONSOLE_USER'"
    HARDENING_WARN=$((HARDENING_WARN + 1))
  fi
fi

# ===========================================================================
# 2. Remove the LaunchAgent plist.
# ===========================================================================
if [ -f "$AGENT_DST" ]; then
  run_step "Remove ${AGENT_DST}" /bin/rm -f "$AGENT_DST"
else
  mark_skip "LaunchAgent plist already absent ($AGENT_DST)"
fi

# ===========================================================================
# 3. Remove the watchdog script and installed lib copy.
# ===========================================================================
if [ -f "$WATCHDOG_DST" ]; then
  run_step "Remove ${WATCHDOG_DST}" /bin/rm -f "$WATCHDOG_DST"
else
  mark_skip "Watchdog already absent ($WATCHDOG_DST)"
fi
# Remove our lib dir if now empty (best effort; rmdir fails if not empty).
run_step_warn "Remove ${LIB_DIR} (if empty)" /bin/rmdir "$LIB_DIR"
run_step_warn "Remove /usr/local/lib/lib/common.sh" /bin/rm -f "/usr/local/lib/lib/common.sh"
run_step_warn "Remove /usr/local/lib/lib (if empty)" /bin/rmdir "/usr/local/lib/lib"

# ===========================================================================
# 4. Remove the configuration profile by identifier.
#    On a managed fleet the MDM owns the profile -- remove it there instead.
#    Set LAZYBOX_SKIP_PROFILE=1 to skip local removal.
# ===========================================================================
if [ -n "${LAZYBOX_SKIP_PROFILE:-}" ]; then
  mark_skip "Profile removal skipped (LAZYBOX_SKIP_PROFILE set; remove via MDM)"
else
  run_step "Remove configuration profile (${PROFILE_IDENT})" \
    /usr/bin/profiles remove -identifier "$PROFILE_IDENT"
fi

summary; exit $?
