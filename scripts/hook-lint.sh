#!/usr/bin/env bash
# hook-lint.sh — Write|Edit hook checks for ios-from-web-guide.
# Called by the PreToolUse and PostToolUse hooks in hooks/hooks.json.
#
# Claude Code feeds a hook's STDERR to the model on exit code 2 (stdout is
# reserved for JSON hook output), so every finding here is written to stderr.
#
# Modes:
#   pre   Blocking checks, run against the EFFECTIVE post-edit content:
#         for Write that is the pending `content`; for Edit it is the on-disk
#         file with `old_string` replaced by `new_string` (so edits that
#         introduce a violation into existing context are caught too).
#         Exit 2 blocks the write and the model sees the findings.
#   post  Warning checks, run against the file now on disk. Exit 2 feeds the
#         findings back to the model without undoing the write.
#
# Usage: hook-lint.sh <pre|post>

set -u

MODE="${1:-}"
INPUT=$(cat)

case "$MODE" in pre|post) ;; *) echo "hook-lint.sh: unknown mode: $MODE" >&2; exit 0 ;; esac

# Parse stdin JSON → file path + a file holding the content to lint.
# pre: writes the effective post-edit content to a temp file.
# post: points at the real file on disk.
DATA=$(printf '%s' "$INPUT" | python3 -c '
import json, sys, os, tempfile

mode = sys.argv[1]
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
ti = d.get("tool_input", {})
fp = ti.get("file_path", "") or ""
if not fp:
    sys.exit(0)

if mode == "post":
    print(fp)
    print(fp)
    sys.exit(0)

if ti.get("content") is not None:
    content = ti["content"]
else:
    base = ""
    try:
        with open(fp) as f:
            base = f.read()
    except Exception:
        pass
    old = ti.get("old_string") or ""
    new = ti.get("new_string") or ""
    if old and old in base:
        content = base.replace(old, new) if ti.get("replace_all") else base.replace(old, new, 1)
    elif new:
        content = base + "\n" + new
    else:
        content = base

fd, tp = tempfile.mkstemp(prefix="iosfwg-hook-")
with os.fdopen(fd, "w") as f:
    f.write(content)
print(fp)
print(tp)
' "$MODE" 2>/dev/null)

FILE_PATH=$(printf '%s\n' "$DATA" | sed -n '1p')
CONTENT_PATH=$(printf '%s\n' "$DATA" | sed -n '2p')

cleanup() {
  if [ "$MODE" = "pre" ] && [ -n "${CONTENT_PATH:-}" ] && [ "$CONTENT_PATH" != "$FILE_PATH" ]; then
    rm -f "$CONTENT_PATH"
  fi
}
trap cleanup EXIT

[ -n "$FILE_PATH" ] && [ -r "$CONTENT_PATH" ] || exit 0

EXT="${FILE_PATH##*.}"
CACHE="$(pwd)/.ios-from-web-guide-project.json"

FINDINGS=()
add() { FINDINGS+=("$1"); }

# ---------------------------------------------------------------- pre checks

check_userdefaults_token() {
  if grep -qiE 'UserDefaults.*(^|[^A-Za-z0-9_])(token|password|secret|api_?key|bearer|credential)([^A-Za-z0-9_]|$)' "$CONTENT_PATH" 2>/dev/null; then
    add '🚫 Storing secrets in UserDefaults detected.
   💡 Fix: Use KeychainService.save(token:) / .getToken() / .deleteToken(). Never UserDefaults for secrets.
   See: ios-auth-keychain-storage skill'
  fi
}

check_navlink_plain() {
  if grep -A 20 'NavigationLink' "$CONTENT_PATH" 2>/dev/null | grep -q 'buttonStyle(\.plain)'; then
    add '🚫 .buttonStyle(.plain) inside a NavigationLink detected.
   💡 Fix: Use .buttonStyle(.borderless) for tappable content inside a NavigationLink — with .plain the tap is absorbed and the link/button interplay breaks.
   See: swiftui-navigation-foundations skill'
  fi
}

# --------------------------------------------------------------- post checks

check_url_relative() {
  if grep -qE 'URL\(string:[[:space:]]*"/' "$CONTENT_PATH" 2>/dev/null; then
    add '⚠️  URL(string:) with a relative path — this returns a schemeless URL and AsyncImage shows the placeholder forever.
   💡 Fix: Use .asBackendURL on the string.
   See: swiftui-async-image-with-backend-paths skill'
  fi
}

check_dispatchqueue_mainactor() {
  if grep -q '@MainActor' "$CONTENT_PATH" 2>/dev/null && grep -q 'DispatchQueue\.main\.async' "$CONTENT_PATH" 2>/dev/null; then
    add '⚠️  DispatchQueue.main.async in a file using @MainActor — likely redundant.
   💡 Fix: Code isolated to @MainActor already runs on the main actor; delete the dispatch (or use await MainActor.run only from nonisolated code).'
  fi
}

check_published_on_ios17() {
  [ -f "$CACHE" ] || return 0
  local target major
  target=$(grep -o '"deployment_target":[[:space:]]*"[^"]*"' "$CACHE" | sed -nE 's/.*"([0-9]+(\.[0-9]+)?)".*/\1/p')
  major="${target%%.*}"
  [ -n "$major" ] || return 0
  [ "$major" -ge 17 ] 2>/dev/null || return 0
  if grep -qE '@Published|@ObservedObject|@StateObject' "$CONTENT_PATH" 2>/dev/null; then
    add '⚠️  @Published/@ObservedObject/@StateObject on iOS 17+ — prefer @Observable.
   💡 Fix: Use the @Observable macro with @State/@Bindable. The ObservableObject pattern is obsolete on iOS 17+.
   See: swiftui-observable-viewmodel-boilerplate skill'
  fi
}

check_print_outside_tests() {
  if printf '%s' "$FILE_PATH" | grep -qE '(Tests?|_test)\.swift$|Tests?/|/SnapshotTests/'; then return 0; fi
  if grep -qE '(^|[[:space:]]|\{|;)print\(' "$CONTENT_PATH" 2>/dev/null; then
    add "⚠️  print() outside test files — this ships to production.
   💡 Fix: Use os.Logger:
     import os
     let logger = Logger(subsystem: \"com.example.app\", category: \"feature\")
     logger.info(\"message\")"
  fi
}

check_hashable_id_eq() {
  local collapsed body
  collapsed=$(tr '\n' ' ' < "$CONTENT_PATH" 2>/dev/null)
  if printf '%s' "$collapsed" | grep -qE 'struct[[:space:]]+[A-Z][A-Za-z0-9_]*[[:space:]]*:[^{]*Hashable'; then
    body=$(printf '%s' "$collapsed" | grep -oE 'static func ==[^{]*\{[^}]*\}' | head -1)
    if [ -n "$body" ] && printf '%s' "$body" | grep -qE 'lhs\.id[[:space:]]*==[[:space:]]*rhs\.id' && ! printf '%s' "$body" | grep -q '&&'; then
      add '⚠️  Custom id-only == on a Hashable struct — this breaks SwiftUI diffing (mutations to non-id fields never re-render).
   💡 Fix: Remove the custom == and let Swift auto-synthesize structural equality. If you need identity-only equality for navigation routing, wrap the id in a separate route type.
   See: swiftui-equatable-hashable-for-diffing skill'
    fi
  fi
}

check_views_checklist_suggestion() {
  if printf '%s' "$FILE_PATH" | grep -qE '/Views/'; then
    add '💡 View file written — consider dispatching the swiftui-checklist agent on it to catch navigation/state/equality/layout pitfalls.'
  fi
}

# -------------------------------------------------------------------- driver

if [ "$MODE" = "pre" ]; then
  [ "$EXT" = "swift" ] || exit 0
  check_userdefaults_token
  check_navlink_plain
else
  [ "$EXT" = "swift" ] || exit 0
  check_url_relative
  check_dispatchqueue_mainactor
  check_published_on_ios17
  check_print_outside_tests
  check_hashable_id_eq
  check_views_checklist_suggestion
fi

if [ ${#FINDINGS[@]} -gt 0 ]; then
  for f in "${FINDINGS[@]}"; do
    printf '%s\n\n' "$f" >&2
  done
  exit 2
fi
exit 0
