# Changelog

## 1.1.0 — 2026-07-03

### Fixed

**Hook feedback never reached the model.** Claude Code feeds a hook's *stderr* to the model on exit code 2, and exit-1 "warnings" are shown to the user only. Every hook message was written to stdout, so blocking hooks blocked without explanation and all warning hooks were silent no-ops (the same failure class as 1.0.1). All findings now go to stderr, and warning checks moved from PreToolUse exit 1 (invisible) to PostToolUse exit 2 (fed back to the model after the write, without undoing it).

**Edits were effectively unlintable.** Checks ran against the bare `new_string`, so an Edit introducing a violation into existing context (e.g. switching `.borderless` to `.plain` inside a NavigationLink already on disk) passed clean. PreToolUse checks now lint the *effective* post-edit content (on-disk file with the replacement applied); PostToolUse checks lint the final file on disk.

**Pre-archive validator false-positived on the plugin's own canonical layout.** It only searched `./Info.plist` at the repo root, but the recommended structure nests it at `<AppName>/Info.plist` and `project.yml.template` inlines keys under `info.properties`. The validator now finds the plist anywhere in the tree and also accepts keys declared in `project.yml`.

**Check regressions (all covered by the new test suite):**
- Force-push guard: `git push origin main --force` (flag after branch) bypassed the block; `--force-with-lease` and branch names merely containing "master" were falsely blocked.
- `userdefaults-token` missed camelCase `apiKey`; now case-insensitive over token/password/secret/api_key/apiKey/bearer/credential.
- `navlink-plain` only matched `NavigationLink(value:`; now matches every NavigationLink form.
- `url-relative` exempted every path starting with `/h` (stray `[^h]` in the regex).
- `dispatchqueue-mainactor` only caught the first method of a type.
- `print-outside-tests` flagged Swift-conventional `FooTests.swift` while exempting Go-style `_test.swift`.
- `print()` detection missed mid-line calls (`func a() { print(...) }`).

**Dark/tinted icon variants are no longer flagged for alpha.** Apple instructs a *transparent* background for the dark variant; the no-alpha rule (ITMS-90717) applies only to the primary icon. The validator now skips `*dark*`/`*tinted*` PNGs and the `ios-app-icon-asset-prep` skill documents the per-variant rules (primary: opaque RGB; dark: transparent; tinted: fully opaque grayscale encoded as RGB).

**Swift 6 template fixes.** `APIClient` is now `@MainActor` (an unisolated `static let shared` holding non-Sendable JSONEncoder/JSONDecoder does not compile under strict concurrency), `KeychainService` is `Sendable` and derives its service name from `Bundle.main.bundleIdentifier` instead of a hardcoded plugin string, and `project.yml.template` gains `SWIFT_STRICT_CONCURRENCY: complete` and `xcodeVersion: "16.0"` (Swift 6 needs Xcode 16).

### Changed

- Hooks consolidated: one `bash-guard.sh` call for Bash and one `hook-lint.sh pre` / `post` call per Write/Edit (was 8 separate PreToolUse invocations, each spawning its own python3).
- `xcrun simctl erase all` now asks for explicit user confirmation (JSON `permissionDecision: "ask"`) instead of an invisible warning.
- `detect_project.sh` writes its cache only when the directory is actually an iOS project (no more junk files in every repo) and announces detection into session context.
- The always-on "did you invoke the skill?" reminder hook was removed — it fired on every write regardless of content; the skill→file mapping lives in `CLAUDE.md.template`, and real findings now actually reach the model.
- Skill frontmatter cleaned up: removed unsupported `file_patterns`/`auto_suggest` fields; trigger conditions folded into `description`.
- Prose hook IDs (H-W-2…H-W-8) replaced with check names; dangling `swiftui-cross-view-state-sync` references removed.

### Added

- `tests/run-tests.sh` — 33-test suite over all scripts (the 1.0.1 bug and this release's stdout bug are both the "silent no-op" class a smoke test catches).
- GitHub Actions CI: test suite on macOS + Linux, shellcheck, JSON validation.
- `templates/APIClientProtocol.swift` and `templates/MockAPIClient.swift` — the injection seam and test double that `ios-feature-scaffold`'s generated ViewModel/tests referenced but nothing provided.

## 1.0.1 — 2026-04-21

### Fixed

All 9 Write|Edit hooks were silent no-ops: they referenced `$CLAUDE_HOOK_FILE_PATH`, an env var Claude Code does not set. The hooks ran but saw empty input and exited 0. Hooks now parse tool input from stdin JSON via a new `scripts/hook-lint.sh` dispatcher, and check the pending `content` / `new_string` rather than a nonexistent file path.

The Bash hooks (force-push and simctl blocks) were also reworked to parse `tool_input.command` properly instead of grepping the raw JSON payload — previously they worked incidentally because the command text appeared in the JSON, but could false-positive on unrelated JSON keys.

## 1.0.0 — 2026-04-20

Initial release.

### Skills (12)

**Track A — iOS client + SwiftUI pitfalls (10):**
- `ios-project-structure` — opinionated folder layout, XcodeGen baseline.
- `ios-api-client-foundation` — `APIClient` with snake_case coding, auth injection.
- `ios-auth-keychain-storage` — tokens live in Keychain, never UserDefaults.
- `ios-feature-scaffold` — model → viewmodel → view → API method loop.
- `swiftui-observable-viewmodel-boilerplate` — `@Observable` only, no `@Published`.
- `swiftui-navigation-foundations` — `NavigationStack` + `NavigationLink(value:)` + `navigationDestination(for:)`.
- `swiftui-layout-pitfalls` — `containerRelativeFrame`, ScrollView clipping, safe-area handling.
- `swiftui-equatable-hashable-for-diffing` — let Swift synthesize; no custom id-only `==`.
- `swiftui-async-image-with-backend-paths` — always resolve relative paths via `.asBackendURL`.
- `swiftui-optimistic-ui-pattern` — optimistic mutation + rollback on error.

**Track B — App Store shipping (2):**
- `ios-info-plist-privacy-strings` — every permission has its usage description.
- `ios-app-icon-asset-prep` — RGB, no alpha, correct sizes.

### Hooks (13)

**SessionStart (1):**
- Project detection — caches `is_ios_project`, `deployment_target`, `uses_xcodegen`, `has_swiftui`, `bundle_id` in `.ios-from-web-guide-project.json` for other hooks to consult.

**PreToolUse — Bash (2):**
- Block dangerous Bash (force push to main/master → exit 2; `xcrun simctl erase all` → warn exit 1).
- Pre-archive validator — on any `xcodebuild ... archive`, delegates to `validate_pre_archive.sh` (build-number increment, alpha-free icon, privacy strings, release config).

**PreToolUse — Write|Edit (8):**
- Skill invocation reminder on `.swift`/`.plist`/`project.yml` (context-aware via project-cache).
- Block `UserDefaults` storage of tokens/passwords/secrets (exit 2).
- Block `.buttonStyle(.plain)` inside `NavigationLink` — use `.borderless` (exit 2).
- Warn on `URL(string:)` with relative path — use `.asBackendURL` (exit 1).
- Warn on `DispatchQueue.main.async` inside a `@MainActor` class/struct (exit 1).
- Warn on `@Published`/`@ObservedObject`/`@StateObject` in iOS 17+ projects — prefer `@Observable` (exit 1).
- Warn on `print()` outside test files — use `os.Logger` (exit 1).
- Warn on custom id-only `==` on a `Hashable` struct — breaks SwiftUI diffing (exit 1).

**PostToolUse — Write|Edit (1):**
- On writes into `/Views/`, suggest running the `swiftui-checklist` agent.

**SubagentStart (1):**
- Inject a condensed rules block (navigation, state, API/auth, shipping, layout) into every subagent.

### Agents (2)

- `swiftui-checklist` — reviews a Swift file for navigation, state, equality, and layout pitfalls.
- `ios-project-structure-review` — reviews overall project layout against the opinionated baseline.

### Templates (7)

`APIClient.swift`, `KeychainService.swift`, `String+BackendURL.swift`, `Configuration.swift`, `AppState.swift`, `project.yml.template`, `AppIcon-Contents.json.template`.

### Scripts (3)

- `detect_project.sh` — writes the session cache file.
- `strip-alpha-from-icon.sh` — removes alpha channel from a PNG (ImageMagick primary, `sips` fallback).
- `validate_pre_archive.sh` — 6-check pre-archive validator (build number, icon alpha, privacy strings, release config, development team, bundle id).

### Distribution

Distributed as a Claude Code plugin via the `ios-from-web-guide` marketplace. Install with `/plugin marketplace add j-morgan6/ios-from-web-guide` + `/plugin install ios-from-web-guide@ios-from-web-guide`. Skills, agents, and hooks activate automatically.
