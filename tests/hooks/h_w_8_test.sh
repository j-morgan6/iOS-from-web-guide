#!/usr/bin/env bash
# tests/hooks/h_w_8_test.sh
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
        if 'id-only' in desc or ('hashable' in desc and '==' in desc):
            print(h['command'])
            sys.exit(0)
sys.exit(1)
PY
)
[ -n "$CMD" ] || fail "H-W-8 command not found"

WORK=$(mktemp -d)

run_hook() {
  local file="$1"
  CLAUDE_HOOK_FILE_PATH="$file" bash -c "$CMD"
  return $?
}

# Dirty: id-only custom ==
cat > "$WORK/Bad.swift" <<'EOF'
import Foundation

struct Post: Hashable {
    let id: UUID
    let title: String

    static func == (lhs: Post, rhs: Post) -> Bool {
        lhs.id == rhs.id
    }
}
EOF
run_hook "$WORK/Bad.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 1 ] || fail "id-only == should warn (exit 1), got $rc"

# Clean: structural Hashable (no custom ==)
cat > "$WORK/Good.swift" <<'EOF'
import Foundation

struct Post: Hashable {
    let id: UUID
    let title: String
}
EOF
run_hook "$WORK/Good.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] || fail "structural Hashable should exit 0 (got $rc)"

# Custom == but compound — shouldn't warn
cat > "$WORK/Compound.swift" <<'EOF'
import Foundation

struct Post: Hashable {
    let id: UUID
    let title: String

    static func == (lhs: Post, rhs: Post) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
    }
}
EOF
run_hook "$WORK/Compound.swift" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] || fail "compound == should exit 0 (got $rc)"

rm -rf "$WORK"
echo "h_w_8_test.sh passed"
