#!/usr/bin/env bash
# tests/hooks/h_w_4_test.sh
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
        if 'url(string' in desc or 'relative path' in desc:
            print(h['command'])
            sys.exit(0)
sys.exit(1)
PY
)
[ -n "$CMD" ] || fail "H-W-4 command not found"

WORK=$(mktemp -d)

run_hook() {
  local file="$1"
  CLAUDE_HOOK_FILE_PATH="$file" bash -c "$CMD"
  return $?
}

# Dirty: relative path
cat > "$WORK/Bad.swift" <<'EOF'
import Foundation
let url = URL(string: "/api/posts")
EOF
run_hook "$WORK/Bad.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 1 ] || fail "relative URL should warn (exit 1), got $rc"

# Clean: absolute path
cat > "$WORK/Good.swift" <<'EOF'
import Foundation
let url = URL(string: "https://api.example.com/posts")
EOF
run_hook "$WORK/Good.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] || fail "absolute URL should exit 0 (got $rc)"

rm -rf "$WORK"
echo "h_w_4_test.sh passed"
