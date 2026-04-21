#!/usr/bin/env bash
# tests/hooks/h_p_1_test.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }

CMD=$(python3 - "$ROOT/hooks-settings.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
for entry in d['hooks'].get('PostToolUse', []):
    for h in entry.get('hooks', []):
        desc = h.get('description', '').lower()
        if 'swiftui-checklist' in desc or 'checklist' in desc:
            print(h['command'])
            sys.exit(0)
sys.exit(1)
PY
)
[ -n "$CMD" ] || fail "H-P-1 command not found"

run_hook() {
  local file="$1"
  CLAUDE_HOOK_FILE_PATH="$file" bash -c "$CMD"
  return $?
}

# .swift under /Views/ → emits suggestion
OUT=$(run_hook "/tmp/App/Views/Foo.swift" 2>&1)
rc=$?
[ $rc -eq 0 ] || fail "hook should exit 0 (got $rc)"
echo "$OUT" | grep -qi 'swiftui-checklist' || fail "should mention swiftui-checklist (got: $OUT)"

# .swift NOT under Views/ → no suggestion
OUT=$(run_hook "/tmp/App/Models/Foo.swift" 2>&1)
echo "$OUT" | grep -qi 'swiftui-checklist' && fail "non-Views .swift should NOT mention swiftui-checklist"

# non-.swift → no suggestion
OUT=$(run_hook "/tmp/App/Views/Readme.md" 2>&1)
echo "$OUT" | grep -qi 'swiftui-checklist' && fail "non-swift should NOT mention swiftui-checklist"

echo "h_p_1_test.sh passed"
