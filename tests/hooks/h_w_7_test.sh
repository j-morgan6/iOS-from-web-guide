#!/usr/bin/env bash
# tests/hooks/h_w_7_test.sh
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
        if 'print' in desc and ('logger' in desc or 'os.log' in desc or 'test' in desc):
            print(h['command'])
            sys.exit(0)
sys.exit(1)
PY
)
[ -n "$CMD" ] || fail "H-W-7 command not found"

WORK=$(mktemp -d)
mkdir -p "$WORK/Sources" "$WORK/Tests" "$WORK/SnapshotTests"

run_hook() {
  local file="$1"
  CLAUDE_HOOK_FILE_PATH="$file" bash -c "$CMD"
  return $?
}

# Dirty: print() in source file
cat > "$WORK/Sources/Bad.swift" <<'EOF'
import Foundation
func foo() {
    print("hello")
}
EOF
run_hook "$WORK/Sources/Bad.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 1 ] || fail "print() in source should warn (exit 1), got $rc"

# Clean: no print
cat > "$WORK/Sources/Good.swift" <<'EOF'
import Foundation
import os
let logger = Logger(subsystem: "com.example", category: "app")
func foo() {
    logger.info("hello")
}
EOF
run_hook "$WORK/Sources/Good.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] || fail "clean file should exit 0 (got $rc)"

# Test file: skip
cat > "$WORK/Tests/FooTests.swift" <<'EOF'
import XCTest
func test() {
    print("debug")
}
EOF
run_hook "$WORK/Tests/FooTests.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] || fail "Tests/ path should be skipped (got $rc)"

# _test.swift suffix: skip
cat > "$WORK/Sources/foo_test.swift" <<'EOF'
func bar() {
    print("yo")
}
EOF
run_hook "$WORK/Sources/foo_test.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] || fail "_test.swift should be skipped (got $rc)"

# SnapshotTests/: skip
cat > "$WORK/SnapshotTests/Snap.swift" <<'EOF'
func bar() {
    print("yo")
}
EOF
run_hook "$WORK/SnapshotTests/Snap.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] || fail "SnapshotTests/ path should be skipped (got $rc)"

rm -rf "$WORK"
echo "h_w_7_test.sh passed"
