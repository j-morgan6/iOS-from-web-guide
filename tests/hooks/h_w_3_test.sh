#!/usr/bin/env bash
# tests/hooks/h_w_3_test.sh
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
        if 'navigationlink' in desc and 'plain' in desc:
            print(h['command'])
            sys.exit(0)
sys.exit(1)
PY
)
[ -n "$CMD" ] || fail "H-W-3 command not found"

WORK=$(mktemp -d)

run_hook() {
  local file="$1"
  CLAUDE_HOOK_FILE_PATH="$file" bash -c "$CMD"
  return $?
}

# Dirty fixture: .plain inside NavigationLink
cat > "$WORK/Bad.swift" <<'EOF'
import SwiftUI

struct Foo: View {
    var body: some View {
        NavigationLink(value: foo) {
            VStack {
                Text("hi")
                Button("tap") {}
                    .buttonStyle(.plain)
            }
        }
    }
}
EOF
run_hook "$WORK/Bad.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 2 ] || fail ".plain inside NavigationLink should exit 2 (got $rc)"

# Clean fixture
cat > "$WORK/Good.swift" <<'EOF'
import SwiftUI

struct Foo: View {
    var body: some View {
        NavigationLink(value: foo) {
            Button("tap") {}
                .buttonStyle(.borderless)
        }
    }
}
EOF
run_hook "$WORK/Good.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] || fail "borderless inside NavigationLink should exit 0 (got $rc)"

rm -rf "$WORK"
echo "h_w_3_test.sh passed"
