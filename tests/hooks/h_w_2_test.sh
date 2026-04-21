#!/usr/bin/env bash
# tests/hooks/h_w_2_test.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }

CMD=$(python3 - "$ROOT/hooks-settings.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for entry in d['hooks'].get('PreToolUse', []):
    if entry.get('matcher') != 'Write|Edit':
        continue
    for h in entry.get('hooks', []):
        desc = h.get('description', '').lower()
        if 'userdefaults' in desc or 'keychain' in desc:
            print(h['command'])
            sys.exit(0)
sys.exit(1)
PY
)
[ -n "$CMD" ] || fail "H-W-2 command not found"

WORK=$(mktemp -d)

run_hook() {
  local file="$1"
  CLAUDE_HOOK_FILE_PATH="$file" bash -c "$CMD"
  return $?
}

# Dirty fixture
cat > "$WORK/Bad.swift" <<'EOF'
import Foundation
UserDefaults.standard.set(token, forKey: "token")
EOF
run_hook "$WORK/Bad.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 2 ] || fail "UserDefaults with token should exit 2 (got $rc)"

# Clean fixture
cat > "$WORK/Good.swift" <<'EOF'
import Foundation
let x = 1
EOF
run_hook "$WORK/Good.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] || fail "clean swift file should exit 0 (got $rc)"

# Non-swift file (skip)
echo "UserDefaults.standard.set(token, forKey: \"token\")" > "$WORK/Bad.txt"
run_hook "$WORK/Bad.txt" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] || fail "non-swift file should exit 0 (got $rc)"

rm -rf "$WORK"
echo "h_w_2_test.sh passed"
