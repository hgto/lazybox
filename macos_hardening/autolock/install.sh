#!/bin/bash
# macos_hardening/autolock/install.sh
#
# Resilient installer for the lazybox autolock component.
#
# Installs, in order:
#   1. The authoritative configuration profile (com.apple.screensaver payload:
#      idleTime=60, askForPassword=1, askForPasswordDelay=0, loginWindowIdleTime=60).
#   2. The defense-in-depth idle-lock watchdog script -> /usr/local/lib/lazybox/.
#   3. The LaunchAgent plist -> /Library/LaunchAgents/.
#   4. Bootstraps the agent into the console user's GUI session.
#
# Resilient: sources the shared lib, wraps every action in run_step, never
# uses `set -e`, and ends with `summary; exit $?`.
#
# SAFETY NOTE: this file is intended to be RUN ON A MANAGED ADMIN MACHINE.
# It performs state-changing operations (profiles install, file copies,
# launchctl bootstrap). Do not run it casually.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

require_macos
# shellcheck disable=SC2119  # require_root takes no args here
require_root

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
PROFILE="${SCRIPT_DIR}/com.lazybox.autolock.mobileconfig"
WATCHDOG_SRC="${SCRIPT_DIR}/idle-lock.sh"
AGENT_SRC="${SCRIPT_DIR}/com.lazybox.idlelock.plist"

LIB_DIR="/usr/local/lib/lazybox"
WATCHDOG_DST="${LIB_DIR}/idle-lock.sh"
AGENT_DST="/Library/LaunchAgents/com.lazybox.idlelock.plist"
AGENT_LABEL="com.lazybox.idlelock"

CONSOLE_USER="$(console_user)"

# ===========================================================================
# 1. Install the configuration profile (the AUTHORITATIVE mechanism).
#
#    *** MANAGED FLEET ***: On a managed fleet you deliver this profile via
#    your MDM (Jamf / Kandji / Intune / Mosyle ...) as a custom/.mobileconfig
#    payload. In that case SKIP this staging step entirely -- the MDM owns
#    profile lifecycle, and a manually-installed profile can conflict with MDM
#    state. Set LAZYBOX_SKIP_PROFILE=1 to skip.
#
#    Standalone macOS (26+) can no longer install profiles from the CLI, so we
#    STAGE the profile (open it for approval in System Settings > Profiles).
#    Defense in depth: the idle-lock watchdog below enforces lock regardless of
#    whether the profile is approved.
# ===========================================================================
if [ -n "${LAZYBOX_SKIP_PROFILE:-}" ]; then
  mark_skip "Profile install skipped (LAZYBOX_SKIP_PROFILE set; deliver via MDM)"
elif [ ! -f "$PROFILE" ]; then
  log_err "Profile not found at $PROFILE"
  HARDENING_FAIL=$((HARDENING_FAIL + 1))
else
  stage_profile "$PROFILE"
fi

# ===========================================================================
# 2. Install the watchdog script to /usr/local/lib/lazybox/.
# ===========================================================================
run_step "Create ${LIB_DIR}" /bin/mkdir -p "$LIB_DIR"

if [ -f "$WATCHDOG_SRC" ]; then
  run_step "Copy idle-lock.sh -> ${WATCHDOG_DST}" \
    /bin/cp "$WATCHDOG_SRC" "$WATCHDOG_DST"
  run_step "chmod 755 ${WATCHDOG_DST}" /bin/chmod 755 "$WATCHDOG_DST"
  run_step "chown root:wheel ${WATCHDOG_DST}" /usr/sbin/chown root:wheel "$WATCHDOG_DST"
else
  log_err "Watchdog source not found at $WATCHDOG_SRC"
  HARDENING_FAIL=$((HARDENING_FAIL + 1))
fi

# NOTE: the watchdog also sources ../lib/common.sh relative to itself, i.e.
# /usr/local/lib/common.sh. Make that available next to the install dir.
if [ -f "${SCRIPT_DIR}/../lib/common.sh" ]; then
  run_step "Create /usr/local/lib/lib" /bin/mkdir -p "/usr/local/lib/lib"
  run_step "Copy common.sh -> /usr/local/lib/lib/common.sh" \
    /bin/cp "${SCRIPT_DIR}/../lib/common.sh" "/usr/local/lib/lib/common.sh"
else
  log_warn "lib/common.sh not found; watchdog will not be able to source it"
fi

# ===========================================================================
# 3. Install the LaunchAgent plist to /Library/LaunchAgents/.
# ===========================================================================
if [ -f "$AGENT_SRC" ]; then
  run_step "Copy LaunchAgent -> ${AGENT_DST}" /bin/cp "$AGENT_SRC" "$AGENT_DST"
  run_step "chown root:wheel ${AGENT_DST}" /usr/sbin/chown root:wheel "$AGENT_DST"
  run_step "chmod 644 ${AGENT_DST}" /bin/chmod 644 "$AGENT_DST"
else
  log_err "LaunchAgent source not found at $AGENT_SRC"
  HARDENING_FAIL=$((HARDENING_FAIL + 1))
fi

# ===========================================================================
# 4. Bootstrap the agent into the console user's GUI session.
#    Must target gui/<uid> (not system) because the agent needs a GUI session
#    to lock the screen.
# ===========================================================================
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
  mark_skip "No console GUI user logged in; agent will load at next user login"
else
  CONSOLE_UID="$(/usr/bin/id -u "$CONSOLE_USER" 2>/dev/null)"
  if [ -z "$CONSOLE_UID" ]; then
    log_warn "Could not resolve uid for console user '$CONSOLE_USER'; skipping bootstrap"
    HARDENING_WARN=$((HARDENING_WARN + 1))
  else
    # bootout first (idempotent) so a re-install reloads cleanly; ignore the
    # failure if it was not already loaded.
    run_step_warn "Bootout existing agent (if loaded)" \
      /bin/launchctl bootout "gui/${CONSOLE_UID}/${AGENT_LABEL}"
    run_step "Bootstrap agent into gui/${CONSOLE_UID}" \
      /bin/launchctl bootstrap "gui/${CONSOLE_UID}" "$AGENT_DST"
    run_step_warn "Kickstart agent" \
      /bin/launchctl kickstart -k "gui/${CONSOLE_UID}/${AGENT_LABEL}"
  fi
fi

summary; exit $?
