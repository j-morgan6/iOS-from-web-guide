#!/usr/bin/env bash
# hook-lint.sh — Write|Edit hook checks for ios-from-web-guide.
# Called by PreToolUse and PostToolUse hooks in hooks/hooks.json.
#
# Claude Code passes tool input as JSON on stdin. This script parses that JSON
# to extract file_path + new content, then runs the named check against them.
#
# Usage: hook-lint.sh <check-name>

set -u

CHECK="${1:-}"
INPUT=$(cat)

DATA=$(printf '%s' "$INPUT" | python3 -c '
import json, sys, os, tempfile
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print("")
    print("")
    sys.exit(0)
ti = d.get("tool_input", {})
fp = ti.get("file_path", "") or ""
content = ti.get("content") or ti.get("new_string") or ""
fd, tp = tempfile.mkstemp(prefix="iosfwg-hook-")
with os.fdopen(fd, "w") as f:
    f.write(content)
print(fp)
print(tp)
' 2>/dev/null)

FILE_PATH=$(printf '%s\n' "$DATA" | sed -n '1p')
CONTENT_PATH=$(printf '%s\n' "$DATA" | sed -n '2p')

cleanup() { [ -n "${CONTENT_PATH:-}" ] && rm -f "$CONTENT_PATH"; }
trap cleanup EXIT

EXT="${FILE_PATH##*.}"
CACHE="$(pwd)/.ios-from-web-guide-project.json"

case "$CHECK" in
  skill-reminder)
    if [ "$EXT" = "swift" ] || [ "$EXT" = "plist" ] || [ "$(basename "$FILE_PATH")" = "project.yml" ]; then
      if [ -f "$CACHE" ]; then
        IS_IOS=$(grep -o '"is_ios_project":[[:space:]]*[a-z]*' "$CACHE" | grep -o '[a-z]*$')
        [ "$IS_IOS" = "false" ] && exit 0
      fi
      echo '💡 Reminder: Did you invoke the relevant ios-from-web-guide skill before writing this file? If not, invoke it now and verify your code follows the rules.'
    fi
    exit 0
    ;;

  userdefaults-token)
    [ "$EXT" != "swift" ] && exit 0
    if grep -qE 'UserDefaults.*\b(token|password|secret|api_key|bearer)\b' "$CONTENT_PATH" 2>/dev/null; then
      echo '🚫 Storing secrets in UserDefaults detected.'
      echo ''
      echo '   💡 Fix: Use KeychainService.save(token:) / .getToken() / .deleteToken(). Never UserDefaults for secrets.'
      echo ''
      echo '   See: ios-auth-keychain-storage skill'
      exit 2
    fi
    exit 0
    ;;

  navlink-plain)
    [ "$EXT" != "swift" ] && exit 0
    if grep -A 20 'NavigationLink(value:' "$CONTENT_PATH" 2>/dev/null | grep -q 'buttonStyle(.plain)'; then
      echo '🚫 .buttonStyle(.plain) inside NavigationLink detected.'
      echo ''
      echo '   💡 Fix: Use .buttonStyle(.borderless) inside NavigationLink. .plain only strips styling; .borderless claims tap ownership so the NavigationLink fires correctly.'
      echo ''
      echo '   See: swiftui-navigation-foundations skill'
      exit 2
    fi
    exit 0
    ;;

  url-relative)
    [ "$EXT" != "swift" ] && exit 0
    if grep -qE 'URL\(string:[[:space:]]*"/[^h]' "$CONTENT_PATH" 2>/dev/null; then
      echo '⚠️  URL(string:) with a relative path — this returns nil.'
      echo ''
      echo '   💡 Fix: Use .asBackendURL on the string. Relative paths resolve to nil in URL(string:).'
      echo ''
      echo '   See: swiftui-async-image-with-backend-paths skill'
      exit 1
    fi
    exit 0
    ;;

  dispatchqueue-mainactor)
    [ "$EXT" != "swift" ] && exit 0
    COLLAPSED=$(tr '\n' ' ' < "$CONTENT_PATH" 2>/dev/null)
    if echo "$COLLAPSED" | grep -qE '@MainActor[^{]*(class|struct|actor)[^{]*\{[^}]*DispatchQueue\.main\.async'; then
      echo '⚠️  DispatchQueue.main.async inside @MainActor is redundant.'
      echo ''
      echo '   💡 Fix: Remove it. All methods on @MainActor already run on the main actor.'
      exit 1
    fi
    exit 0
    ;;

  published-on-ios17)
    [ "$EXT" != "swift" ] && exit 0
    [ -f "$CACHE" ] || exit 0
    TARGET=$(grep -o '"deployment_target":[[:space:]]*"[^"]*"' "$CACHE" | sed -E 's/.*"([0-9.]+)".*/\1/')
    MAJOR=$(echo "$TARGET" | cut -d. -f1)
    [ -z "$MAJOR" ] && exit 0
    if [ "$MAJOR" -lt 17 ] 2>/dev/null; then exit 0; fi
    if grep -qE '@Published|@ObservedObject|@StateObject' "$CONTENT_PATH" 2>/dev/null; then
      echo '⚠️  @Published/@ObservedObject/@StateObject on iOS 17+ — prefer @Observable.'
      echo ''
      echo '   💡 Fix: Use @Observable (Swift Observation framework). iOS 17+ makes the old ObservableObject pattern obsolete.'
      echo ''
      echo '   See: swiftui-observable-viewmodel-boilerplate skill'
      exit 1
    fi
    exit 0
    ;;

  print-outside-tests)
    [ "$EXT" != "swift" ] && exit 0
    if echo "$FILE_PATH" | grep -qE '_test\.swift$|/Tests/|/SnapshotTests/'; then exit 0; fi
    if grep -qE '^[[:space:]]*print\(' "$CONTENT_PATH" 2>/dev/null; then
      echo "⚠️  print() call outside test files — shouldnt ship."
      echo ''
      echo '   💡 Fix: Replace print() with os.Logger for production logging.'
      echo ''
      echo '     import os'
      echo '     let logger = Logger(subsystem: "com.example.app", category: "feature")'
      echo '     logger.info("message")'
      exit 1
    fi
    exit 0
    ;;

  hashable-id-eq)
    [ "$EXT" != "swift" ] && exit 0
    COLLAPSED=$(tr '\n' ' ' < "$CONTENT_PATH" 2>/dev/null)
    if echo "$COLLAPSED" | grep -qE 'struct[[:space:]]+[A-Z][A-Za-z0-9_]*[[:space:]]*:[^{]*Hashable'; then
      BODY=$(echo "$COLLAPSED" | grep -oE 'static func ==[^{]*\{[^}]*\}' | head -1)
      if [ -n "$BODY" ] && echo "$BODY" | grep -qE 'lhs\.id[[:space:]]*==[[:space:]]*rhs\.id' && ! echo "$BODY" | grep -q '&&'; then
        echo '⚠️  Custom id-only `==` detected on a Hashable struct — this breaks SwiftUI diffing.'
        echo ''
        echo '   💡 Fix: Remove the custom `==` and let Swift auto-synthesize structural equality:'
        echo ''
        echo '     struct Post: Hashable { ... }  // no custom == needed'
        echo ''
        echo '   If you need identity-only equality for navigation routing, wrap the id in a separate Identifiable-only type.'
        echo ''
        echo '   See: swiftui-equatable-hashable-for-diffing skill'
        exit 1
      fi
    fi
    exit 0
    ;;

  post-write-views)
    [ "$EXT" != "swift" ] && exit 0
    if echo "$FILE_PATH" | grep -qE '/Views/'; then
      echo '💡 Consider running the swiftui-checklist agent on this file to catch common pitfalls (navigation, state, equality, layout).'
    fi
    exit 0
    ;;

  *)
    echo "hook-lint.sh: unknown check: $CHECK" >&2
    exit 0
    ;;
esac
