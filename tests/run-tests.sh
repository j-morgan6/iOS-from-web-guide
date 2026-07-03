#!/usr/bin/env bash
# Test suite for ios-from-web-guide scripts.
# Run: bash tests/run-tests.sh
#
# Contract under test (v1.1.0):
#   - All hook feedback goes to STDERR (Claude Code feeds stderr to the model
#     on exit 2; stdout is reserved for JSON hook output).
#   - hook-lint.sh has two aggregate modes:
#       pre  — blocking checks against the EFFECTIVE post-edit content
#              (Write: pending content; Edit: on-disk file with old_string
#              replaced by new_string). Exit 2 + stderr on violation.
#       post — warning checks against the file now on disk. Exit 2 + stderr
#              when there are findings (PostToolUse exit 2 feeds Claude
#              without undoing the write).
#   - bash-guard.sh handles the Bash PreToolUse checks (force-push block,
#     simctl erase-all ask, pre-archive delegation).
#   - validate_pre_archive.sh finds Info.plist anywhere in the tree (the
#     canonical layout nests it) and greps project.yml info.properties too.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_LINT="$ROOT/scripts/hook-lint.sh"
BASH_GUARD="$ROOT/scripts/bash-guard.sh"
VALIDATOR="$ROOT/scripts/validate_pre_archive.sh"
DETECT="$ROOT/scripts/detect_project.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

# run <stdin-json> <cmd...>  — captures OUT, ERR, CODE
run() {
  local stdin_data="$1"; shift
  local out_f err_f
  out_f=$(mktemp); err_f=$(mktemp)
  printf '%s' "$stdin_data" | "$@" >"$out_f" 2>"$err_f"
  CODE=$?
  OUT=$(cat "$out_f"); ERR=$(cat "$err_f")
  rm -f "$out_f" "$err_f"
}

check() { # <name> <condition-description> <pass:0/1>
  local name="$1" desc="$2" ok="$3"
  if [ "$ok" = "0" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); FAILED_NAMES+=("$name: $desc")
    echo "FAIL $name — $desc"
    echo "     exit=$CODE"
    echo "     stdout: $(printf '%s' "$OUT" | head -3)"
    echo "     stderr: $(printf '%s' "$ERR" | head -3)"
  fi
}

expect() { # <name> <expected-exit> <stream:err|out|none> <substring-or-empty>
  local name="$1" want_code="$2" stream="$3" substr="${4:-}"
  local ok=0
  [ "$CODE" = "$want_code" ] || ok=1
  case "$stream" in
    err)  printf '%s' "$ERR" | grep -qF "$substr" || ok=1 ;;
    out)  printf '%s' "$OUT" | grep -qF "$substr" || ok=1 ;;
    none) [ -z "$OUT$ERR" ] || ok=1 ;;
  esac
  check "$name" "want exit=$want_code ${stream}~'$substr'" "$ok"
}

# JSON helpers
write_json() { # file_path content
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":sys.argv[2]}}))' "$1" "$2"
}
edit_json() { # file_path old new
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Edit","tool_input":{"file_path":sys.argv[1],"old_string":sys.argv[2],"new_string":sys.argv[3]}}))' "$1" "$2" "$3"
}
bash_json() { # command
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1"
}

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

###############################################################################
echo "== hook-lint.sh pre (blocking, effective content, stderr) =="
###############################################################################

WORK="$TMPROOT/pre"; mkdir -p "$WORK"; cd "$WORK" || exit 1

run "$(write_json "$WORK/Auth.swift" 'UserDefaults.standard.set(token, forKey: "auth_token")')" bash "$HOOK_LINT" pre
expect P1-userdefaults-token 2 err "Keychain"

run "$(write_json "$WORK/Auth.swift" 'UserDefaults.standard.set(apiKey, forKey: "apiKey")')" bash "$HOOK_LINT" pre
expect P2-userdefaults-camelcase 2 err "Keychain"

# Edit that introduces .plain into a NavigationLink that only exists on disk
cat > "$WORK/Card.swift" <<'EOF'
struct Card: View {
    var body: some View {
        NavigationLink(value: post) {
            Button("Like") { like() }
                .buttonStyle(.borderless)
        }
    }
}
EOF
run "$(edit_json "$WORK/Card.swift" '.buttonStyle(.borderless)' '.buttonStyle(.plain)')" bash "$HOOK_LINT" pre
expect P3-edit-context-navlink 2 err "borderless"

run "$(write_json "$WORK/V.swift" 'NavigationLink(destination: DetailView()) { Button("Like"){}.buttonStyle(.plain) }')" bash "$HOOK_LINT" pre
expect P4-navlink-destination-form 2 err "borderless"

run "$(write_json "$WORK/Clean.swift" 'struct A: View { var body: some View { Text("hi") } }')" bash "$HOOK_LINT" pre
expect P5-clean-swift 0 none

run "$(write_json "$WORK/notes.md" 'UserDefaults token password')" bash "$HOOK_LINT" pre
expect P6-non-swift 0 none

# A NavigationLink with .borderless must NOT be blocked
run "$(write_json "$WORK/Ok.swift" 'NavigationLink(value: post) { Button("Like"){}.buttonStyle(.borderless) }')" bash "$HOOK_LINT" pre
expect P7-borderless-ok 0 none

###############################################################################
echo "== hook-lint.sh post (warnings, on-disk file, stderr, exit 2) =="
###############################################################################

WORK="$TMPROOT/post"; mkdir -p "$WORK/App/Sources" "$WORK/App/Views" "$WORK/AppTests"; cd "$WORK" || exit 1

post_run() { # file relpath, content
  local f="$WORK/$1"
  printf '%s\n' "$2" > "$f"
  run "$(write_json "$f" "$2")" bash "$HOOK_LINT" post
}

post_run "App/Sources/Feed.swift" 'func a() { print("debug") }'
expect Q1-print-warns 2 err "Logger"

post_run "AppTests/FeedViewModelTests.swift" 'func t() { print("debug") }'
expect Q2-print-tests-suffix-ok 0 none

post_run "App/Sources/Img.swift" 'let u = URL(string: "/health/check.png")'
expect Q3-url-relative-h-path 2 err "asBackendURL"

post_run "App/Sources/VM.swift" '@MainActor final class VM {
    func a() { }
    func b() { DispatchQueue.main.async { self.x = 1 } }
}'
expect Q4-dispatchqueue-second-method 2 err "MainActor"

# published-on-ios17 needs the project cache in cwd
printf '{\n  "is_ios_project": true,\n  "deployment_target": "17.0"\n}\n' > "$WORK/.ios-from-web-guide-project.json"
post_run "App/Sources/OldVM.swift" 'final class VM: ObservableObject { @Published var items: [Int] = [] }'
expect Q5-published-ios17 2 err "Observable"

post_run "App/Sources/Post.swift" 'struct Post: Identifiable, Hashable {
    let id: Int
    var title: String
    static func == (lhs: Post, rhs: Post) -> Bool { lhs.id == rhs.id }
}'
expect Q6-hashable-id-eq 2 err "diffing"

post_run "App/Sources/Fine.swift" 'struct Fine { let a: Int }'
expect Q7-clean 0 none

post_run "App/Views/FeedView.swift" 'struct FeedView: View { var body: some View { Text("x") } }'
expect Q8-views-suggestion 2 err "swiftui-checklist"

###############################################################################
echo "== bash-guard.sh =="
###############################################################################

WORK="$TMPROOT/guard"; mkdir -p "$WORK"; cd "$WORK" || exit 1

run "$(bash_json 'git push -f origin main')" bash "$BASH_GUARD"
expect B1-force-push-classic 2 err "force"

run "$(bash_json 'git push origin main --force')" bash "$BASH_GUARD"
expect B2-force-flag-after-branch 2 err "force"

run "$(bash_json 'git push --force-with-lease origin main')" bash "$BASH_GUARD"
expect B3-force-with-lease-allowed 0 none

run "$(bash_json 'git push --force origin feature-remaster')" bash "$BASH_GUARD"
expect B4-branch-substring-not-blocked 0 none

run "$(bash_json 'git push -f origin HEAD:main')" bash "$BASH_GUARD"
expect B5-refspec-main 2 err "force"

run "$(bash_json 'xcrun simctl erase all')" bash "$BASH_GUARD"
expect B6-simctl-erase-ask 0 out '"permissionDecision": "ask"'

run "$(bash_json 'git push origin feature-x')" bash "$BASH_GUARD"
expect B7-plain-push 0 none

# archive delegation: run in a dir where the validator must fail (empty team)
mkdir -p "$WORK/arch"; cd "$WORK/arch" || exit 1
printf 'name: App\nsettings:\n  base:\n    DEVELOPMENT_TEAM:\n' > project.yml
run "$(bash_json 'xcodebuild -scheme App archive')" bash "$BASH_GUARD"
expect B8-archive-delegates-validator 2 err "DEVELOPMENT_TEAM"

###############################################################################
echo "== validate_pre_archive.sh =="
###############################################################################

# V1: canonical nested layout, key present → must PASS (1.0.1 false-positive)
WORK="$TMPROOT/v1"; mkdir -p "$WORK/MyApp/Views"; cd "$WORK" || exit 1
printf 'name: MyApp\nsettings:\n  base:\n    DEVELOPMENT_TEAM: ABC123\n' > project.yml
printf 'import PhotosUI\nstruct V {}\n' > MyApp/Views/Picker.swift
cat > MyApp/Info.plist <<'EOF'
<plist><dict>
<key>NSPhotoLibraryUsageDescription</key><string>MyApp needs photo access.</string>
<key>ITSAppUsesNonExemptEncryption</key><false/>
</dict></plist>
EOF
run "" bash "$VALIDATOR"
expect V1-nested-plist-passes 0 out "passed"

# V2: key genuinely missing → fail with the key name on stderr
WORK="$TMPROOT/v2"; mkdir -p "$WORK/MyApp/Views"; cd "$WORK" || exit 1
printf 'name: MyApp\nsettings:\n  base:\n    DEVELOPMENT_TEAM: ABC123\n' > project.yml
printf 'import PhotosUI\nstruct V {}\n' > MyApp/Views/Picker.swift
printf '<plist><dict><key>ITSAppUsesNonExemptEncryption</key><false/></dict></plist>' > MyApp/Info.plist
run "" bash "$VALIDATOR"
expect V2-missing-privacy-string 2 err "NSPhotoLibraryUsageDescription"

# V3: keys inlined in project.yml info.properties (no standalone plist) → pass
WORK="$TMPROOT/v3"; mkdir -p "$WORK/MyApp/Views"; cd "$WORK" || exit 1
cat > project.yml <<'EOF'
name: MyApp
settings:
  base:
    DEVELOPMENT_TEAM: ABC123
targets:
  MyApp:
    info:
      path: MyApp/Info.plist
      properties:
        ITSAppUsesNonExemptEncryption: false
        NSPhotoLibraryUsageDescription: "MyApp needs photo access."
EOF
printf 'import PhotosUI\nstruct V {}\n' > MyApp/Views/Picker.swift
run "" bash "$VALIDATOR"
expect V3-inline-properties-pass 0 out "passed"

# V4: empty DEVELOPMENT_TEAM → fail
WORK="$TMPROOT/v4"; mkdir -p "$WORK"; cd "$WORK" || exit 1
printf 'name: App\nsettings:\n  base:\n    DEVELOPMENT_TEAM:\n' > project.yml
run "" bash "$VALIDATOR"
expect V4-empty-team 2 err "DEVELOPMENT_TEAM"

# V5: build number not bumped → fail; bumped → pass
WORK="$TMPROOT/v5"; mkdir -p "$WORK"; cd "$WORK" || exit 1
printf 'name: App\nsettings:\n  base:\n    DEVELOPMENT_TEAM: ABC\n    CURRENT_PROJECT_VERSION: 5\n    ITSAppUsesNonExemptEncryption: false\n' > project.yml
printf '{"version":"7"}\n' > .build-history
run "" bash "$VALIDATOR"
expect V5a-build-number-stale 2 err "CURRENT_PROJECT_VERSION"
printf 'name: App\nsettings:\n  base:\n    DEVELOPMENT_TEAM: ABC\n    CURRENT_PROJECT_VERSION: 8\n    ITSAppUsesNonExemptEncryption: false\n' > project.yml
run "" bash "$VALIDATOR"
expect V5b-build-number-bumped 0 out "passed"

# V6: skip hatch
run "" env IOS_FROM_WEB_SKIP_VALIDATOR=1 bash "$VALIDATOR"
expect V6-skip-hatch 0 out "skipped"

###############################################################################
echo "== detect_project.sh =="
###############################################################################

# D1: non-iOS directory → no cache file, quiet
WORK="$TMPROOT/d1"; mkdir -p "$WORK"; cd "$WORK" || exit 1
printf 'hello\n' > readme.txt
run "" bash "$DETECT"
D1_OK=0
[ "$CODE" = "0" ] || D1_OK=1
[ ! -f .ios-from-web-guide-project.json ] || D1_OK=1
check D1-non-ios-no-cache "no cache file in non-iOS dir" "$D1_OK"

# D2: unquoted deployment target parses
WORK="$TMPROOT/d2"; mkdir -p "$WORK"; cd "$WORK" || exit 1
printf 'name: App\noptions:\n  deploymentTarget:\n    iOS: 17.0\n' > project.yml
run "" bash "$DETECT"
D2_OK=0
[ "$CODE" = "0" ] || D2_OK=1
grep -q '"deployment_target": "17.0"' .ios-from-web-guide-project.json 2>/dev/null || D2_OK=1
printf '%s' "$OUT" | grep -qi 'ios' || D2_OK=1   # SessionStart stdout announcement
check D2-unquoted-target "cache written, target parsed, announcement on stdout" "$D2_OK"

# D3: quoted deployment target parses
WORK="$TMPROOT/d3"; mkdir -p "$WORK"; cd "$WORK" || exit 1
printf 'name: App\noptions:\n  deploymentTarget:\n    iOS: "17.0"\n' > project.yml
run "" bash "$DETECT"
D3_OK=0
grep -q '"deployment_target": "17.0"' .ios-from-web-guide-project.json 2>/dev/null || D3_OK=1
check D3-quoted-target "quoted target parsed" "$D3_OK"

###############################################################################
echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || { printf '  - %s\n' "${FAILED_NAMES[@]}"; exit 1; }
exit 0
