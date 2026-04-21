#!/usr/bin/env bash
# tests/hooks/h_sa_1_test.sh
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "FAIL: $1"; exit 1; }

CMD=$(python3 - "$ROOT/hooks-settings.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
entries = d['hooks'].get('SubagentStart', [])
if not entries:
    sys.exit(1)
print(entries[0]['hooks'][0]['command'])
PY
)
[ -n "$CMD" ] || fail "H-SA-1 command not found"

OUT=$(printf '' | bash -c "$CMD")
rc=$?
[ $rc -eq 0 ] || fail "subagent rules hook should exit 0 (got $rc)"

# Assert key phrases
for phrase in \
  "SwiftUI Navigation" \
  "State Management" \
  "API / Auth" \
  "Shipping" \
  "Layout" \
  "buttonStyle(.borderless)" \
  "@Observable" \
  "Keychain" \
  "containerRelativeFrame"; do
  echo "$OUT" | grep -q "$phrase" || fail "missing phrase: $phrase"
done

echo "h_sa_1_test.sh passed"
