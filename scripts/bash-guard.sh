#!/usr/bin/env bash
# bash-guard.sh — PreToolUse(Bash) guard for ios-from-web-guide.
#
# 1. Blocks force-pushes that target main/master (exit 2; stderr reaches the
#    model). `--force-with-lease` is allowed.
# 2. Downgrades `xcrun simctl erase all` to an explicit user confirmation via
#    JSON permissionDecision "ask" on stdout.
# 3. Delegates any `xcodebuild ... archive` to validate_pre_archive.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    d = json.loads(sys.stdin.read())
    print(d.get("tool_input", {}).get("command", ""))
except Exception:
    pass' 2>/dev/null)

[ -n "$CMD" ] || exit 0

# --- force push to main/master -----------------------------------------------
# Requires all three, in any order: a git push, a bare -f/--force flag (NOT
# --force-with-lease), and main/master as a word (branch arg or refspec dest).
if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+push' \
  && printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(-f|--force)([[:space:]]|$)' \
  && printf '%s' "$CMD" | grep -qE '(^|[[:space:]:/])(main|master)([[:space:]:]|$)'; then
  {
    echo '🚫 Force push targeting main/master rewrites shared history.'
    echo '   Use --force-with-lease on a feature branch, or push to a new branch.'
  } >&2
  exit 2
fi

# --- simctl erase all → ask the user ------------------------------------------
if printf '%s' "$CMD" | grep -qE 'xcrun[[:space:]]+simctl[[:space:]]+erase[[:space:]]+all'; then
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "xcrun simctl erase all wipes ALL simulator state. Prefer `xcrun simctl erase <device-udid>` for a single device."
  }
}
JSON
  exit 0
fi

# --- pre-archive validation ----------------------------------------------------
if printf '%s' "$CMD" | grep -qE 'xcodebuild[[:space:]].*archive'; then
  bash "$SCRIPT_DIR/validate_pre_archive.sh"
  exit $?
fi

exit 0
