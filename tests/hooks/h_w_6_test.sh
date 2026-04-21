#!/usr/bin/env bash
# tests/hooks/h_w_6_test.sh
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
        if '@published' in desc or 'observable' in desc:
            print(h['command'])
            sys.exit(0)
sys.exit(1)
PY
)
[ -n "$CMD" ] || fail "H-W-6 command not found"

WORK=$(mktemp -d)
cd "$WORK"

run_hook() {
  local file="$1"
  CLAUDE_HOOK_FILE_PATH="$file" bash -c "$CMD"
  return $?
}

# Create cache indicating iOS 17+
cat > .ios-from-web-guide-project.json <<EOF
{
  "is_ios_project": true,
  "has_swiftui": true,
  "deployment_target": "17.0",
  "uses_xcodegen": true,
  "has_swift_package": false,
  "bundle_id": "com.example.app"
}
EOF

# Dirty fixture
cat > "$WORK/Bad.swift" <<'EOF'
import SwiftUI

class FooViewModel: ObservableObject {
    @Published var items: [Int] = []
}
EOF
run_hook "$WORK/Bad.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 1 ] || fail "@Published in iOS 17+ should warn (exit 1), got $rc"

# Clean fixture
cat > "$WORK/Good.swift" <<'EOF'
import SwiftUI

@Observable
class FooViewModel {
    var items: [Int] = []
}
EOF
run_hook "$WORK/Good.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] || fail "clean @Observable class should exit 0 (got $rc)"

# iOS 16 project: no warning even for @Published
cat > .ios-from-web-guide-project.json <<EOF
{
  "is_ios_project": true,
  "has_swiftui": true,
  "deployment_target": "16.0",
  "uses_xcodegen": true,
  "has_swift_package": false,
  "bundle_id": "com.example.app"
}
EOF
run_hook "$WORK/Bad.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] || fail "@Published in iOS 16 should exit 0 (got $rc)"

cd - >/dev/null
rm -rf "$WORK"
echo "h_w_6_test.sh passed"
