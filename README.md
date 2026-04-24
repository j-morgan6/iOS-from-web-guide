# ios-from-web-guide

Enforce iOS/SwiftUI best practices when adding a native iOS client to an existing web app.

**12 skills · 13 hooks · 2 agents · 7 templates · 4 scripts**

A Claude Code plugin. Targets SwiftUI, iOS 17+, XcodeGen, and the App Store release pipeline. Pairs enforced skills with `PreToolUse`/`PostToolUse`/`SessionStart`/`SubagentStart` hooks and opinionated templates so common mistakes are caught before they ship.

## What it solves

Five concrete scars from shipping a real iOS client on top of a web backend:

1. **NavigationLink tap absorption.** `.buttonStyle(.plain)` inside a `NavigationLink` silently eats the tap. Hook H-W-3 blocks this; skill `swiftui-navigation-foundations` teaches it.
2. **Hashable diffing broken by custom `==`.** A custom id-only `==` on a model struct makes SwiftUI think nothing changed. Hook H-W-8 warns; skill `swiftui-equatable-hashable-for-diffing` explains.
3. **VStack + ScrollView clipping.** Intrinsic sizing on a ScrollView child collapses width. Skill `swiftui-layout-pitfalls` covers `containerRelativeFrame` and sibling issues.
4. **`URL(string:)` with a relative path returns nil.** Hook H-W-4 warns; skill `swiftui-async-image-with-backend-paths` + template `String+BackendURL.swift` give the fix.
5. **Alpha in the app icon rejects at App Store upload.** `validate_pre_archive.sh` catches it before Archive; `strip-alpha-from-icon.sh` fixes it.

Plus a handful of "one-hour-to-recover" pitfalls: UserDefaults-for-tokens (blocked), `@Published` when iOS 17 wants `@Observable`, `DispatchQueue.main.async` inside `@MainActor`, `print()` shipping to production, missing privacy strings, non-incrementing build number.

## Quick start

Install via Claude Code's plugin system:

```
/plugin marketplace add j-morgan6/iOS-from-web-guide
/plugin install ios-from-web-guide@ios-from-web-guide
```

Restart Claude Code. Skills, agents, and hooks load automatically.

Drop `CLAUDE.md.template` into your iOS project root (it tells Claude which skills to invoke when):

```bash
cp ~/.claude/plugins/cache/ios-from-web-guide/ios-from-web-guide/*/CLAUDE.md.template ./CLAUDE.md
```

### Uninstall

```
/plugin uninstall ios-from-web-guide@ios-from-web-guide
```

## Documentation

- **[CHANGELOG.md](CHANGELOG.md)** — release history.
- **[CLAUDE.md.template](CLAUDE.md.template)** — drop-in project file that tells Claude which skills to invoke on which files.

## License

MIT. See [LICENSE](LICENSE).
