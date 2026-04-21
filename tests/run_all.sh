#!/usr/bin/env bash
# Runs every *_test.sh under tests/. Each test script is responsible for its own
# assertions and exits 0 on pass, non-zero on fail. Aggregates results.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FAILED=0
PASSED=0
for t in tests/scripts/*_test.sh tests/hooks/*_test.sh; do
  [ -f "$t" ] || continue
  echo "=== $t ==="
  if bash "$t"; then
    PASSED=$((PASSED + 1))
    echo "PASS"
  else
    FAILED=$((FAILED + 1))
    echo "FAIL"
  fi
  echo
done
echo "Summary: $PASSED passed, $FAILED failed"
exit $FAILED
