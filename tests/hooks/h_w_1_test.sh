#!/usr/bin/env bash
# tests/hooks/h_w_1_test.sh
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
        if 'remind' in desc and 'skill' in desc:
            print(h['command'])
            sys.exit(0)
sys.exit(1)
PY
)
[ -n "$CMD" ] || fail "H-W-1 command not found"

WORK=$(mktemp -d)
cd "$WORK"

run_hook() {
  local file="$1"
  CLAUDE_HOOK_FILE_PATH="$file" bash -c "$CMD"
  return $?
}

# Case: .swift file — emits reminder
echo "import SwiftUI" > foo.swift
OUT=$(run_hook "$WORK/foo.swift" 2>&1)
rc=$?
[ $rc -eq 0 ] || fail ".swift should exit 0 (got $rc)"
echo "$OUT" | grep -qi 'reminder' || fail ".swift should emit reminder (got: $OUT)"

# Case: .plist file — emits reminder
OUT=$(run_hook "$WORK/Info.plist" 2>&1)
echo "$OUT" | grep -qi 'reminder' || fail ".plist should emit reminder"

# Case: project.yml — emits reminder
OUT=$(run_hook "$WORK/project.yml" 2>&1)
echo "$OUT" | grep -qi 'reminder' || fail "project.yml should emit reminder"

# Case: .txt file — no reminder
OUT=$(run_hook "$WORK/readme.txt" 2>&1)
echo "$OUT" | grep -qi 'reminder' && fail ".txt should NOT emit reminder"

# Case: is_ios_project: false in cache — skip reminder for .swift
cat > .ios-from-web-guide-project.json <<EOF
{
  "is_ios_project": false,
  "has_swiftui": false,
  "deployment_target": "",
  "uses_xcodegen": false,
  "has_swift_package": false,
  "bundle_id": ""
}
EOF
OUT=$(run_hook "$WORK/foo.swift" 2>&1)
echo "$OUT" | grep -qi 'reminder' && fail "non-iOS project should NOT emit reminder"

cd - >/dev/null
rm -rf "$WORK"
echo "h_w_1_test.sh passed"
