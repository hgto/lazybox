#!/bin/bash
# darwin/autoupgrade/install.sh
#
# Installs the brew-autoupgrade LaunchAgent for the current user.
#   1. Copies brew-autoupgrade script -> ~/.local/bin/ (chmod 700)
#   2. Expands @@HOME@@ in the plist template and copies to ~/Library/LaunchAgents/
#   3. Bootstraps (or re-bootstraps) the LaunchAgent into the user's GUI session
#
# Does NOT require root — everything goes into the user's home directory.
# Safe to re-run; idempotent.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_LABEL="com.lazybox.brew-autoupgrade"
SCRIPT_SRC="${SCRIPT_DIR}/brew-autoupgrade"
PLIST_SRC="${SCRIPT_DIR}/com.lazybox.brew-autoupgrade.plist"
SCRIPT_DST="${HOME}/.local/bin/brew-autoupgrade"
PLIST_DST="${HOME}/Library/LaunchAgents/com.lazybox.brew-autoupgrade.plist"

PASS=0; FAIL=0

ok()   { printf '[ OK ] %s\n' "$*"; PASS=$((PASS+1)); }
fail() { printf '[FAIL] %s\n' "$*" >&2; FAIL=$((FAIL+1)); }
info() { printf '[ .. ] %s\n' "$*"; }

require_macos() {
  case "$(uname -s)" in
    Darwin) ;;
    *) fail "This script is macOS-only."; exit 1 ;;
  esac
}

require_macos

# ---------------------------------------------------------------------------
# 1. Script
# ---------------------------------------------------------------------------
info "Installing brew-autoupgrade script -> ${SCRIPT_DST}"
mkdir -p "${HOME}/.local/bin"
if cp "${SCRIPT_SRC}" "${SCRIPT_DST}" && chmod 700 "${SCRIPT_DST}"; then
  ok "brew-autoupgrade installed (chmod 700)"
else
  fail "Failed to install brew-autoupgrade"
fi

# ---------------------------------------------------------------------------
# 2. Plist (expand @@HOME@@ -> actual home path)
# ---------------------------------------------------------------------------
info "Installing LaunchAgent plist -> ${PLIST_DST}"
mkdir -p "${HOME}/Library/LaunchAgents"
if sed "s|@@HOME@@|${HOME}|g" "${PLIST_SRC}" > "${PLIST_DST}"; then
  ok "LaunchAgent plist installed"
else
  fail "Failed to install LaunchAgent plist"
fi

# ---------------------------------------------------------------------------
# 3. Bootstrap (bootout first for idempotent re-install)
# ---------------------------------------------------------------------------
GUI_DOMAIN="gui/$(id -u)"

info "Booting out existing agent (if loaded)"
launchctl bootout "${GUI_DOMAIN}/${AGENT_LABEL}" 2>/dev/null && ok "Existing agent booted out" || true

info "Bootstrapping agent into ${GUI_DOMAIN}"
if launchctl bootstrap "${GUI_DOMAIN}" "${PLIST_DST}"; then
  ok "Agent bootstrapped"
else
  fail "Failed to bootstrap LaunchAgent"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
printf 'Result: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '[FAIL] Installation had errors.\n' >&2
  exit 1
fi
printf '[ OK ] brew-autoupgrade is installed and scheduled daily at 09:00.\n'
printf '       Log: %s/Library/Logs/brew-autoupgrade.log\n' "${HOME}"
printf '       To run now: launchctl kickstart -k %s/%s\n' "${GUI_DOMAIN}" "${AGENT_LABEL}"
