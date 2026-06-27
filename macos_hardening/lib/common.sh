#!/bin/bash
# macos_hardening/lib/common.sh
#
# Shared, resilient foundation for every script in this project.
#
# Design goals (mirroring the project requirements):
#   * Resilient    - a single failing command NEVER aborts the run. Every
#                    step is wrapped so we log, count, and keep going.
#   * Idempotent   - helpers check current state before changing it.
#   * Asserts state- assert_* helpers compare ACTUAL vs EXPECTED and record
#                    a pass/fail without mutating anything (audit mode).
#   * Runs anywhere- pure bash 3.2 (the version Apple ships at /bin/bash).
#                    No associative arrays, no `${x^^}`, no `mapfile`.
#
# Source it from any script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   . "${SCRIPT_DIR}/../lib/common.sh"
#
# Deliberately NOT using `set -e`: we want to continue past failures and
# decide ourselves what is fatal. We DO use nounset + pipefail.
set -uo pipefail

# ----------------------------------------------------------------------------
# Counters (the basis of "assert state" + a CI-friendly exit code)
# ----------------------------------------------------------------------------
HARDENING_PASS=0
HARDENING_FAIL=0
HARDENING_WARN=0
HARDENING_SKIP=0

# ----------------------------------------------------------------------------
# Colors (auto-disabled when not a TTY or when NO_COLOR is set)
# ----------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GRN=$'\033[32m'
  C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_DIM=""
fi

# Optional log file: export HARDENING_LOG=/path/to/file before sourcing.
_log_raw() {
  # $1 = already-formatted line (no color codes go to the file)
  if [ -n "${HARDENING_LOG:-}" ]; then
    printf '%s %s\n' "$(_ts)" "$1" >>"${HARDENING_LOG}" 2>/dev/null || true
  fi
}

_ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }

log_info() { printf '%s[ .. ]%s %s\n' "$C_BLU" "$C_RESET" "$*"; _log_raw "[ .. ] $*"; }
log_ok()   { printf '%s[ OK ]%s %s\n' "$C_GRN" "$C_RESET" "$*"; _log_raw "[ OK ] $*"; }
log_warn() { printf '%s[WARN]%s %s\n' "$C_YEL" "$C_RESET" "$*" >&2; _log_raw "[WARN] $*"; }
log_err()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; _log_raw "[FAIL] $*"; }
log_dim()  { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; _log_raw "$*"; }

# ----------------------------------------------------------------------------
# run_step: execute a command, log the outcome, ALWAYS return 0 so the caller
# keeps going. This is the core resilience primitive.
#
#   run_step "Disable guest account" /usr/sbin/sysadminctl -guestAccount off
# ----------------------------------------------------------------------------
run_step() {
  local desc="$1"; shift
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    HARDENING_PASS=$((HARDENING_PASS + 1))
    log_ok "$desc"
    [ -n "$out" ] && log_dim "      $out"
  else
    HARDENING_FAIL=$((HARDENING_FAIL + 1))
    log_err "$desc (exit $rc)"
    [ -n "$out" ] && log_dim "      $out"
  fi
  return 0
}

# run_step_warn: like run_step but a failure is a WARNing, not a FAIL.
# Use for best-effort / non-critical steps.
run_step_warn() {
  local desc="$1"; shift
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    HARDENING_PASS=$((HARDENING_PASS + 1)); log_ok "$desc"
    [ -n "$out" ] && log_dim "      $out"
  else
    HARDENING_WARN=$((HARDENING_WARN + 1)); log_warn "$desc (exit $rc)"
    [ -n "$out" ] && log_dim "      $out"
  fi
  return 0
}

# ----------------------------------------------------------------------------
# assert_*: VERIFY (audit) helpers. They never mutate; they compare actual vs
# expected and bump the pass/fail counters. Use these in *_verify.sh scripts.
# ----------------------------------------------------------------------------

# assert_eq "description" "expected" "actual"
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    HARDENING_PASS=$((HARDENING_PASS + 1)); log_ok "$desc (= $actual)"
  else
    HARDENING_FAIL=$((HARDENING_FAIL + 1))
    log_err "$desc (expected '$expected', got '$actual')"
  fi
  return 0
}

# assert_cmd "description" "expected" command [args...]
# Runs the command, trims trailing whitespace, compares stdout to expected.
assert_cmd() {
  local desc="$1" expected="$2"; shift 2
  local actual
  actual="$("$@" 2>/dev/null)"; actual="${actual%%[[:space:]]}"
  assert_eq "$desc" "$expected" "$actual"
}

# assert_profile_installed "PayloadIdentifier"
# Confirms a configuration profile is actually installed (system scope).
assert_profile_installed() {
  local ident="$1"
  if /usr/bin/profiles show -output stdout-xml 2>/dev/null | /usr/bin/grep -q "$ident"; then
    HARDENING_PASS=$((HARDENING_PASS + 1)); log_ok "Profile installed: $ident"
  else
    HARDENING_FAIL=$((HARDENING_FAIL + 1)); log_err "Profile NOT installed: $ident"
  fi
  return 0
}

# assert_defaults "description" domain key "expected"  (reads a defaults value)
assert_defaults() {
  local desc="$1" domain="$2" key="$3" expected="$4" actual
  actual="$(/usr/bin/defaults read "$domain" "$key" 2>/dev/null)"
  assert_eq "$desc" "$expected" "$actual"
}

mark_skip() { HARDENING_SKIP=$((HARDENING_SKIP + 1)); log_warn "SKIP: $*"; return 0; }

# ----------------------------------------------------------------------------
# Environment helpers
# ----------------------------------------------------------------------------
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log_err "This script must run as root (try: sudo $0 $*)"
    exit 2
  fi
}

is_macos() { [ "$(uname -s)" = "Darwin" ]; }

require_macos() {
  if ! is_macos; then
    log_err "This script only runs on macOS (uname=$(uname -s))."
    exit 2
  fi
}

macos_version() { /usr/bin/sw_vers -productVersion 2>/dev/null || echo "0"; }
macos_major()   { macos_version | /usr/bin/cut -d. -f1; }

# The currently logged-in GUI user (not root). Empty at the loginwindow.
console_user() {
  /usr/bin/stat -f%Su /dev/console 2>/dev/null || echo ""
}

# ----------------------------------------------------------------------------
# stage_profile <path-to-mobileconfig>
#
# Modern macOS (11+, fully enforced by macOS 26) removed `profiles install`
# from the CLI: a .mobileconfig can only be installed via MDM or by manual
# approval in System Settings. For the standalone path we STAGE the profile by
# opening it in the console user's GUI session. macOS then lists it under
#   System Settings > General > VPN & Device Management
#   (or Privacy & Security > Profiles)
# where the admin approves it within ~8 minutes (after that it is discarded).
# ----------------------------------------------------------------------------
stage_profile() {
  local path="$1" name user uid
  name="$(basename "$path")"
  if [ ! -f "$path" ]; then
    log_err "Profile not found: $path"
    HARDENING_FAIL=$((HARDENING_FAIL + 1))
    return 0
  fi
  user="$(console_user)"
  if [ -z "$user" ] || [ "$user" = "root" ]; then
    mark_skip "Stage ${name}: no console GUI user; approve manually with: open '$path'"
    return 0
  fi
  uid="$(/usr/bin/id -u "$user" 2>/dev/null)"
  if [ -z "$uid" ]; then
    mark_skip "Stage ${name}: could not resolve uid for console user '$user'"
    return 0
  fi
  run_step "Stage ${name} (approve in System Settings > Profiles)" \
    /bin/launchctl asuser "$uid" /usr/bin/sudo -u "$user" /usr/bin/open "$path"
}

# ----------------------------------------------------------------------------
# summary: print totals; exit code reflects failures (0 = clean, 1 = failures).
# Call at the end of every script:  summary; exit $?
# ----------------------------------------------------------------------------
summary() {
  printf '\n%s---- summary ----%s\n' "$C_DIM" "$C_RESET"
  printf '  %spass%s=%d  %sfail%s=%d  %swarn%s=%d  skip=%d\n' \
    "$C_GRN" "$C_RESET" "$HARDENING_PASS" \
    "$C_RED" "$C_RESET" "$HARDENING_FAIL" \
    "$C_YEL" "$C_RESET" "$HARDENING_WARN" "$HARDENING_SKIP"
  _log_raw "summary pass=$HARDENING_PASS fail=$HARDENING_FAIL warn=$HARDENING_WARN skip=$HARDENING_SKIP"
  [ "$HARDENING_FAIL" -eq 0 ]
}
