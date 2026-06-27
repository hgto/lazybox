#!/bin/bash
# mscp/compliance.sh
#
# Thin wrapper around the mSCP-generated *_compliance.sh script.
#
#   ./compliance.sh            -> audit only  (runs the script with --check)
#   sudo ./compliance.sh fix   -> remediate   (runs the script with --fix)
#
# The generated compliance script records its results in an audit plist at
#   /Library/Preferences/org.<baseline>.audit.plist
# where each rule key holds a dict with `finding` (true = NON-compliant) and
# `exempt`. After a --check run we read that plist back and summarize pass/fail
# per rule, feeding the project's pass/fail counters so the exit code is
# CI-meaningful.
#
# SAFETY: --check is read-only (audit). --fix is state-changing and requires
# root. Resilient: no `set -e`; we wrap calls in run_step. End `summary; exit $?`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/../lib/common.sh"

require_macos

BASELINE="${BASELINE:-cis_lvl1}"
BUILD_DIR="${SCRIPT_DIR}/build"

# Mode: default audit; `fix` as $1 switches to remediation.
MODE="check"
if [ "${1:-}" = "fix" ]; then
  MODE="fix"
  require_root "fix"   # remediation must be root
fi

# Locate the generated compliance script in build/.
COMPLIANCE_SH=""
for f in "${BUILD_DIR}"/*_compliance.sh; do
  if [ -e "$f" ]; then COMPLIANCE_SH="$f"; break; fi
done

if [ -z "$COMPLIANCE_SH" ]; then
  log_err "No *_compliance.sh in ${BUILD_DIR}. Run ./generate.sh first."
  summary; exit $?
fi
log_info "Compliance script: $COMPLIANCE_SH"
log_info "Mode: $MODE"

# ----------------------------------------------------------------------------
# Run the compliance script.
#   --check  audit, do not change anything
#   --fix    apply remediations
# ----------------------------------------------------------------------------
if [ "$MODE" = "fix" ]; then
  run_step "Run compliance --fix" /bin/bash "$COMPLIANCE_SH" --fix
else
  run_step "Run compliance --check" /bin/bash "$COMPLIANCE_SH" --check
fi

# ----------------------------------------------------------------------------
# Read back and summarize the audit results plist.
# ----------------------------------------------------------------------------
AUDIT_PLIST="/Library/Preferences/org.${BASELINE}.audit.plist"

if [ ! -f "$AUDIT_PLIST" ]; then
  log_warn "Audit plist not found: $AUDIT_PLIST (was the script run with proper privileges?)"
  summary; exit $?
fi

log_info "Audit results: $AUDIT_PLIST"
log_dim "---- raw plist (plutil -p) ----"
/usr/bin/plutil -p "$AUDIT_PLIST" 2>/dev/null || log_warn "plutil could not read $AUDIT_PLIST"

# Per-rule pass/fail summary.
#
# Each top-level key is a rule id. Its `finding` boolean is true when the rule
# is NON-compliant (a finding). We list rule ids, then for each read its
# finding/exempt and bump the counters.
#
# `defaults read <plist-without-.plist> <key>` returns the dict; we grep the
# nested booleans. We strip the trailing ".plist" because `defaults` wants the
# domain path, not the file name.
DOMAIN="${AUDIT_PLIST%.plist}"

log_dim "---- per-rule summary ----"
RULE_IDS="$(/usr/bin/plutil -convert json -o - "$AUDIT_PLIST" 2>/dev/null \
  | /usr/bin/tr ',{}' '\n' \
  | /usr/bin/grep -Eo '"[a-zA-Z0-9_]+"[[:space:]]*:[[:space:]]*\{' \
  | /usr/bin/sed -E 's/"([^"]+)".*/\1/')"

if [ -z "$RULE_IDS" ]; then
  # Fallback: list keys via defaults if the JSON parse yielded nothing.
  RULE_IDS="$(/usr/bin/defaults read "$DOMAIN" 2>/dev/null \
    | /usr/bin/grep -Eo '^[[:space:]]+[a-zA-Z0-9_]+ =' \
    | /usr/bin/sed -E 's/[^a-zA-Z0-9_]//g')"
fi

if [ -z "$RULE_IDS" ]; then
  log_warn "Could not enumerate rule ids from $AUDIT_PLIST"
  summary; exit $?
fi

# Iterate rule ids (newline-separated; safe under bash 3.2).
OLD_IFS="$IFS"; IFS='
'
for rule in $RULE_IDS; do
  [ -z "$rule" ] && continue
  # finding=true  -> NON-compliant; finding=false -> compliant.
  finding="$(/usr/bin/defaults read "$DOMAIN" "$rule" 2>/dev/null \
    | /usr/bin/grep -E 'finding' | /usr/bin/grep -Eo '[01]' | /usr/bin/head -1)"
  exempt="$(/usr/bin/defaults read "$DOMAIN" "$rule" 2>/dev/null \
    | /usr/bin/grep -E 'exempt' | /usr/bin/grep -Eo '[01]' | /usr/bin/head -1)"
  if [ "$exempt" = "1" ]; then
    mark_skip "$rule (exempt)"
  elif [ "$finding" = "0" ]; then
    HARDENING_PASS=$((HARDENING_PASS + 1)); log_ok "compliant: $rule"
  elif [ "$finding" = "1" ]; then
    HARDENING_FAIL=$((HARDENING_FAIL + 1)); log_err "NON-compliant: $rule"
  else
    HARDENING_WARN=$((HARDENING_WARN + 1)); log_warn "unknown result: $rule"
  fi
done
IFS="$OLD_IFS"

summary; exit $?
