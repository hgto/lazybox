#!/bin/bash
# macos_hardening/autolock/idle-lock.sh
#
# Defense-in-depth idle-lock watchdog (belt-and-suspenders).
#
# The AUTHORITATIVE lock policy is delivered by the configuration profile
# (com.lazybox.autolock.mobileconfig). This watchdog exists for UNMANAGED
# devices where the profile cannot be enforced via MDM: it independently
# locks the screen after a period of user inactivity.
#
# How it works:
#   * Reads the human-input idle time from IOKit (HIDIdleTime, nanoseconds).
#   * When idle >= threshold, locks the screen with CGSession -suspend.
#       - CGSession is reliable and needs NO Accessibility/automation grant.
#   * Loops with a short sleep so it reacts promptly after the threshold.
#
# Must run as a LaunchAgent inside the user's GUI session (see the .plist):
# a root LaunchDaemon has no WindowServer session and cannot lock.
#
# Resilient by design: never `set -e`; missing binaries -> warn/skip and keep
# going so launchd's KeepAlive does not hot-loop on a hard failure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "${SCRIPT_DIR}/../lib/common.sh"

# ---------------------------------------------------------------------------
# Configuration
#   Threshold (seconds of inactivity before locking):
#     1. $1 positional arg, else
#     2. $IDLE_THRESHOLD env var, else
#     3. default 60.
#   POLL_INTERVAL: seconds between idle checks (short so we react quickly).
# ---------------------------------------------------------------------------
IDLE_THRESHOLD="${1:-${IDLE_THRESHOLD:-60}}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"

IOREG="/usr/sbin/ioreg"
AWK="/usr/bin/awk"
CGSESSION="/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"

# ---------------------------------------------------------------------------
# get_idle_seconds: print whole seconds of HID (keyboard/mouse) idle time.
# HIDIdleTime is reported in nanoseconds; divide by 1e9. Prints "" on failure.
# ---------------------------------------------------------------------------
get_idle_seconds() {
  # shellcheck disable=SC2016  # $NF is an awk field ref, must stay literal
  "$IOREG" -c IOHIDSystem 2>/dev/null \
    | "$AWK" '/HIDIdleTime/ {print int($NF/1000000000); exit}'
}

# ---------------------------------------------------------------------------
# lock_screen: suspend the GUI session (locks immediately).
# ---------------------------------------------------------------------------
lock_screen() {
  "$CGSESSION" -suspend
}

main() {
  log_info "idle-lock watchdog starting (threshold=${IDLE_THRESHOLD}s, poll=${POLL_INTERVAL}s)"

  # Preflight: guard against missing binaries. If a critical tool is absent we
  # cannot do our job, so warn and sleep forever (rather than busy-fail under
  # launchd KeepAlive). The profile remains the authoritative mechanism.
  if [ ! -x "$IOREG" ]; then
    mark_skip "ioreg not found at $IOREG; cannot read idle time"
    while true; do sleep 3600; done
  fi
  if [ ! -x "$AWK" ]; then
    mark_skip "awk not found at $AWK; cannot parse idle time"
    while true; do sleep 3600; done
  fi
  if [ ! -x "$CGSESSION" ]; then
    mark_skip "CGSession not found at $CGSESSION; cannot lock screen"
    while true; do sleep 3600; done
  fi

  log_ok "idle-lock watchdog active"

  while true; do
    idle="$(get_idle_seconds)"

    # If we could not read idle time (transient ioreg hiccup), warn and retry.
    case "$idle" in
      ''|*[!0-9]*)
        log_warn "could not read idle time (got '${idle}'); retrying"
        sleep "$POLL_INTERVAL"
        continue
        ;;
    esac

    if [ "$idle" -ge "$IDLE_THRESHOLD" ]; then
      log_info "idle ${idle}s >= ${IDLE_THRESHOLD}s -> locking screen"
      if lock_screen; then
        log_ok "screen locked (CGSession -suspend)"
      else
        log_warn "CGSession -suspend failed; will retry next cycle"
      fi
      # After locking, back off a little longer so we do not immediately
      # re-trigger before the user has a chance to interact.
      sleep "$POLL_INTERVAL"
    fi

    sleep "$POLL_INTERVAL"
  done
}

main "$@"
