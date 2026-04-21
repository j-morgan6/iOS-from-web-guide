#!/usr/bin/env bash
# tests/hooks/h_b_1_test.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }

CMD=$(python3 - "$ROOT/hooks-settings.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for entry in d['hooks'].get('PreToolUse', []):
    if entry.get('matcher') != 'Bash':
        continue
    for h in entry.get('hooks', []):
        desc = h.get('description', '').lower()
        if 'dangerous' in desc or 'force push' in desc:
            print(h['command'])
            sys.exit(0)
sys.exit(1)
PY
)
[ -n "$CMD" ] || fail "H-B-1 command not found in hooks-settings.json"

run_hook() {
  local input="$1"
  printf '%s' "$input" | bash -c "$CMD"
  return $?
}

# Case: force push to main → exit 2
run_hook '{"command":"git push --force origin main"}' >/dev/null 2>&1
rc=$?
[ $rc -eq 2 ] || fail "force push to main should exit 2 (got $rc)"

# Case: normal git push → exit 0
run_hook '{"command":"git push origin main"}' >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] || fail "normal push should exit 0 (got $rc)"

# Case: simctl erase all → exit 1 (warn)
run_hook '{"command":"xcrun simctl erase all"}' >/dev/null 2>&1
rc=$?
[ $rc -eq 1 ] || fail "simctl erase all should exit 1 (got $rc)"

echo "h_b_1_test.sh passed"
