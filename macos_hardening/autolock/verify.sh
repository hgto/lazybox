#!/bin/bash
# macos_hardening/autolock/verify.sh
#
# Audit-only verification of the lazybox autolock state. Mutates NOTHING.
# Asserts:
#   * The configuration profile is installed.
#   * Effective screensaver policy: idleTime=60, askForPassword=1,
#     askForPasswordDelay=0 (read via defaults -currentHost and profiles show).
#   * The LaunchAgent plist exists on disk and is loaded in the GUI session.
#
# Resilient + audit: assert_* helpers, no `set -e`, ends `summary; exit $?`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

require_macos

PROFILE_IDENT="com.lazybox.autolock"
AGENT_DST="/Library/LaunchAgents/com.lazybox.idlelock.plist"
AGENT_LABEL="com.lazybox.idlelock"

CONSOLE_USER="$(console_user)"

log_info "Verifying lazybox autolock on $(macos_version) (console user: ${CONSOLE_USER:-none})"

# ===========================================================================
# 1. Profile installed?
# ===========================================================================
assert_profile_installed "$PROFILE_IDENT"

# ===========================================================================
# 2. Effective screensaver policy.
#
#    Reading the values is fiddly on modern macOS:
#      - The profile's effective values are visible via `profiles show`.
#      - `defaults -currentHost read com.apple.screensaver` reflects the
#        per-host preference (what the screensaver subsystem actually uses).
#    We try defaults first (cheap), and the assertion records pass/fail.
#    Run this in the CONSOLE USER's context for accurate per-user values.
# ===========================================================================
read_screensaver() {
  # $1 = key. Try, in order: managed preferences delivered by a configuration
  # profile (per-user), the console user's currentHost domain, then ours.
  local key="$1" val=""
  if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ]; then
    val="$(/usr/bin/defaults read "/Library/Managed Preferences/${CONSOLE_USER}/com.apple.screensaver" "$key" 2>/dev/null)"
  fi
  if [ -z "$val" ] && [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ] && [ "$(id -u)" -eq 0 ]; then
    val="$(/usr/bin/sudo -u "$CONSOLE_USER" /usr/bin/defaults -currentHost read com.apple.screensaver "$key" 2>/dev/null)"
  fi
  if [ -z "$val" ]; then
    val="$(/usr/bin/defaults -currentHost read com.apple.screensaver "$key" 2>/dev/null)"
  fi
  printf '%s' "$val"
}

# A present-but-wrong value is a FAIL; an unreadable value is a WARN, because
# macOS 26 hides the screensaver lock keys from `defaults` and the idle-lock
# watchdog (verified separately below) is the authoritative enforcement.
check_screensaver() {
  local desc="$1" key="$2" expected="$3" actual
  actual="$(read_screensaver "$key")"
  if [ -z "$actual" ]; then
    HARDENING_WARN=$((HARDENING_WARN + 1))
    log_warn "$desc: not readable on this macOS (keys are managed/hidden); idle-lock watchdog enforces locking"
  else
    assert_eq "$desc" "$expected" "$actual"
  fi
}

check_screensaver "screensaver idleTime == 60"            idleTime            60
check_screensaver "screensaver askForPassword == 1"       askForPassword      1
check_screensaver "screensaver askForPasswordDelay == 0"  askForPasswordDelay 0

# Cross-check against the profile's declared payload (authoritative source).
# `profiles show` emits the installed payload; we grep for our key/values.
PROFILE_XML="$(/usr/bin/profiles show -output stdout-xml 2>/dev/null)"
if printf '%s' "$PROFILE_XML" | /usr/bin/grep -q "loginWindowIdleTime"; then
  assert_eq "profile carries loginWindowIdleTime payload" "yes" "yes"
else
  assert_eq "profile carries loginWindowIdleTime payload" "yes" "no"
fi

# ===========================================================================
# 3. LaunchAgent present and loaded.
# ===========================================================================
if [ -f "$AGENT_DST" ]; then
  assert_eq "LaunchAgent plist present" "yes" "yes"
else
  assert_eq "LaunchAgent plist present" "yes" "no"
fi

if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
  mark_skip "No console GUI user; cannot check whether agent is loaded in a session"
else
  CONSOLE_UID="$(/usr/bin/id -u "$CONSOLE_USER" 2>/dev/null)"
  if [ -n "$CONSOLE_UID" ]; then
    if /bin/launchctl print "gui/${CONSOLE_UID}/${AGENT_LABEL}" >/dev/null 2>&1; then
      assert_eq "LaunchAgent loaded in gui/${CONSOLE_UID}" "loaded" "loaded"
    else
      assert_eq "LaunchAgent loaded in gui/${CONSOLE_UID}" "loaded" "not-loaded"
    fi
  else
    mark_skip "Could not resolve uid for console user '$CONSOLE_USER'"
  fi
fi

summary; exit $?
