#!/bin/bash
# darwin/autoupgrade/verify.sh
#
# Audit-only: verifies the brew-autoupgrade installation state. Mutates nothing.
# Checks:
#   * brew-autoupgrade script present at ~/.local/bin/ and executable (chmod 700)
#   * LaunchAgent plist present at ~/Library/LaunchAgents/
#   * Agent loaded in the current user's GUI session
#   * Next scheduled fire time (informational)

set -uo pipefail

AGENT_LABEL="com.lazybox.brew-autoupgrade"
SCRIPT_DST="${HOME}/.local/bin/brew-autoupgrade"
PLIST_DST="${HOME}/Library/LaunchAgents/com.lazybox.brew-autoupgrade.plist"
GUI_DOMAIN="gui/$(id -u)"

PASS=0; FAIL=0; WARN=0

ok()   { printf '[ OK ] %s\n' "$*"; PASS=$((PASS+1)); }
fail() { printf '[FAIL] %s\n' "$*" >&2; FAIL=$((FAIL+1)); }
warn() { printf '[WARN] %s\n' "$*"; WARN=$((WARN+1)); }
info() { printf '[ .. ] %s\n' "$*"; }

require_macos() {
  case "$(uname -s)" in
    Darwin) ;;
    *) fail "This script is macOS-only."; exit 1 ;;
  esac
}

require_macos
info "Verifying brew-autoupgrade on $(sw_vers -productName) $(sw_vers -productVersion)"

# ---------------------------------------------------------------------------
# Script
# ---------------------------------------------------------------------------
if [ -f "${SCRIPT_DST}" ]; then
  ok "Script present: ${SCRIPT_DST}"
else
  fail "Script missing: ${SCRIPT_DST}"
fi

if [ -x "${SCRIPT_DST}" ]; then
  perms="$(stat -f '%A' "${SCRIPT_DST}" 2>/dev/null)"
  if [ "${perms}" = "700" ]; then
    ok "Script permissions: 700 (owner-only)"
  else
    warn "Script permissions: ${perms} (expected 700)"
  fi
else
  fail "Script not executable: ${SCRIPT_DST}"
fi

# ---------------------------------------------------------------------------
# Plist
# ---------------------------------------------------------------------------
if [ -f "${PLIST_DST}" ]; then
  ok "LaunchAgent plist present: ${PLIST_DST}"
else
  fail "LaunchAgent plist missing: ${PLIST_DST}"
fi

# ---------------------------------------------------------------------------
# Agent loaded
# ---------------------------------------------------------------------------
if launchctl print "${GUI_DOMAIN}/${AGENT_LABEL}" >/dev/null 2>&1; then
  ok "Agent loaded in ${GUI_DOMAIN}"
  last_exit="$(launchctl print "${GUI_DOMAIN}/${AGENT_LABEL}" 2>/dev/null | grep 'last exit code' | awk '{print $NF}')"
  runs="$(launchctl print "${GUI_DOMAIN}/${AGENT_LABEL}" 2>/dev/null | grep 'runs =' | awk '{print $NF}')"
  info "Runs so far: ${runs:-?}  /  Last exit code: ${last_exit:-(never exited)}"
else
  fail "Agent NOT loaded in ${GUI_DOMAIN}"
fi

# ---------------------------------------------------------------------------
# Log file
# ---------------------------------------------------------------------------
LOG="${HOME}/Library/Logs/brew-autoupgrade.log"
if [ -f "${LOG}" ]; then
  ok "Log file present: ${LOG}"
  info "Last log entry: $(tail -1 "${LOG}")"
else
  warn "Log file not yet created (no runs yet?): ${LOG}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
printf 'Result: %d passed, %d failed, %d warnings\n' "$PASS" "$FAIL" "$WARN"
[ "$FAIL" -gt 0 ] && { printf '[FAIL] Verification failed.\n' >&2; exit 1; }
[ "$WARN" -gt 0 ] && { printf '[WARN] Verification passed with warnings.\n'; exit 0; }
printf '[ OK ] brew-autoupgrade is correctly installed.\n'
