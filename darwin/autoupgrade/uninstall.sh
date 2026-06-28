#!/bin/bash
# darwin/autoupgrade/uninstall.sh
#
# Reverses install.sh:
#   1. Boots out the LaunchAgent from the user's GUI session
#   2. Removes the plist from ~/Library/LaunchAgents/
#   3. Removes the script from ~/.local/bin/

set -uo pipefail

AGENT_LABEL="com.lazybox.brew-autoupgrade"
SCRIPT_DST="${HOME}/.local/bin/brew-autoupgrade"
PLIST_DST="${HOME}/Library/LaunchAgents/com.lazybox.brew-autoupgrade.plist"
GUI_DOMAIN="gui/$(id -u)"

PASS=0; FAIL=0; SKIP=0

ok()   { printf '[ OK ] %s\n' "$*"; PASS=$((PASS+1)); }
fail() { printf '[FAIL] %s\n' "$*" >&2; FAIL=$((FAIL+1)); }
skip() { printf '[SKIP] %s\n' "$*"; SKIP=$((SKIP+1)); }

require_macos() {
  case "$(uname -s)" in
    Darwin) ;;
    *) fail "This script is macOS-only."; exit 1 ;;
  esac
}

require_macos

# ---------------------------------------------------------------------------
# 1. Bootout
# ---------------------------------------------------------------------------
if launchctl print "${GUI_DOMAIN}/${AGENT_LABEL}" >/dev/null 2>&1; then
  if launchctl bootout "${GUI_DOMAIN}/${AGENT_LABEL}"; then
    ok "Agent booted out from ${GUI_DOMAIN}"
  else
    fail "Failed to boot out agent from ${GUI_DOMAIN}"
  fi
else
  skip "Agent not loaded in ${GUI_DOMAIN}"
fi

# ---------------------------------------------------------------------------
# 2. Plist
# ---------------------------------------------------------------------------
if [ -f "${PLIST_DST}" ]; then
  if rm -f "${PLIST_DST}"; then
    ok "Removed ${PLIST_DST}"
  else
    fail "Failed to remove ${PLIST_DST}"
  fi
else
  skip "Plist already absent (${PLIST_DST})"
fi

# ---------------------------------------------------------------------------
# 3. Script
# ---------------------------------------------------------------------------
if [ -f "${SCRIPT_DST}" ]; then
  if rm -f "${SCRIPT_DST}"; then
    ok "Removed ${SCRIPT_DST}"
  else
    fail "Failed to remove ${SCRIPT_DST}"
  fi
else
  skip "Script already absent (${SCRIPT_DST})"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
printf 'Result: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -gt 0 ] && { printf '[FAIL] Uninstall had errors.\n' >&2; exit 1; }
printf '[ OK ] brew-autoupgrade uninstalled.\n'
