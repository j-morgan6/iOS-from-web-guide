---
name: ios-project-structure
description: MANDATORY for iOS project initialization and project.yml work. Invoke before creating or editing project.yml, Package.swift, or the top-level directory layout.
file_patterns:
  - "**/project.yml"
  - "**/Package.swift"
auto_suggest: true
---

# iOS Project Structure

## RULES — Follow these with no exceptions

1. **Use XcodeGen with `project.yml`** — never commit the generated `.xcodeproj` or manual Xcode edits; the `project.yml` is the source of truth.
2. **Set `DEVELOPMENT_TEAM` in `project.yml`**, not in Xcode's signing UI — `xcodegen generate` wipes manual edits on regeneration.
3. **iOS 17.0 deployment target minimum** — required for `@Observable` and `.containerRelativeFrame`.
4. **Swift 6 concurrency enabled** — `SWIFT_VERSION: 6.0`, `SWIFT_STRICT_CONCURRENCY: complete`.
5. **`TARGETED_DEVICE_FAMILY = "1"` (iPhone only)** unless iPad layouts are designed — otherwise App Store rejects for "all interface orientations must be supported".
6. **Portrait-only** by default — `UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait`.
7. **Every top-level Swift source lives under one of:** `App/`, `Models/`, `Services/`, `ViewModels/`, `Views/`, or `Extensions/`. No exceptions — new feature code that doesn't fit means the directory is wrong, not the rule.
8. **`.gitignore` must exclude** `*.xcodeproj/`, `xcuserdata/`, `DerivedData/`, `build/`, `.xcuserstate`, `*.xcworkspace/xcuserdata/`.

---

## When to invoke

- Starting a new iOS project (greenfield scaffold).
- Editing `project.yml` for a new target, config, or build setting.
- Restructuring an existing project that's drifted from the layout.
- Adding a new Swift Package dependency via `Package.swift`.

## The opinionated layout

```
YourApp/
├── project.yml                      # XcodeGen config (source of truth)
├── .gitignore
├── YourApp/
│   ├── App/                         # @main entry, AppState, Configuration
│   │   ├── YourAppApp.swift
│   │   ├── AppState.swift           # @Observable auth state
│   │   └── Configuration.swift      # apiBaseURL from Info.plist
│   ├── Models/                      # Codable structs, Hashable, Sendable
│   │   ├── User.swift
│   │   └── Post.swift
│   ├── Services/                    # APIClient, KeychainService, Push
│   │   ├── APIClient.swift
│   │   └── KeychainService.swift
│   ├── ViewModels/                  # @MainActor @Observable classes
│   │   ├── FeedViewModel.swift
│   │   └── ProfileViewModel.swift
│   ├── Views/
│   │   ├── MainView.swift           # Root NavigationStack + tab container
│   │   ├── Components/              # Reusable UI (BottomBar, BadgePill)
│   │   └── Feed/                    # Per-feature view folders
│   │       ├── FeedView.swift
│   │       └── FeedCardView.swift
│   ├── Extensions/                  # String+BackendURL, Date+TimeAgo
│   │   └── String+BackendURL.swift
│   ├── Assets.xcassets/
│   └── Info.plist
└── YourAppTests/
```

**Why this shape:** maps 1:1 to MVVM + SwiftUI. A new contributor can guess where any file lives in < 5 seconds.

## The canonical `project.yml`

```yaml
name: YourApp
options:
  deploymentTarget:
    iOS: "17.0"
  bundleIdPrefix: com.yourcompany
settings:
  base:
    SWIFT_VERSION: 6.0
    SWIFT_STRICT_CONCURRENCY: complete
    DEVELOPMENT_TEAM: ABCDE12345           # your Apple Team ID
    TARGETED_DEVICE_FAMILY: "1"            # iPhone only
    MARKETING_VERSION: 1.0.0
    CURRENT_PROJECT_VERSION: 1
targets:
  YourApp:
    type: application
    platform: iOS
    sources: [YourApp]
    info:
      path: YourApp/Info.plist
      properties:
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        ITSAppUsesNonExemptEncryption: false
        NSPhotoLibraryUsageDescription: "YourApp needs photo access to upload images."
        NSCameraUsageDescription: "YourApp needs camera access to take photos."
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.yourcompany.yourapp
```

See `<plugin-root>/templates/project.yml.template` for the full canonical version.

## The `.gitignore`

```gitignore
# Xcode
*.xcodeproj/
*.xcworkspace/xcuserdata/
xcuserdata/
*.xcuserstate
DerivedData/
build/

# Swift Package Manager
.swiftpm/
.build/

# macOS
.DS_Store
```

## Common pitfalls

### `xcodegen generate` wipes my team ID

**Cause:** You set `DEVELOPMENT_TEAM` through Xcode's signing UI instead of `project.yml`.

**Fix:** Put it in `project.yml` under `settings.base.DEVELOPMENT_TEAM`. Regenerate. The team ID survives forever.

### Bundled with iPad by default, App Store rejects

**Cause:** `TARGETED_DEVICE_FAMILY` defaults to `"1,2"` — both iPhone and iPad. App Store then requires you to support all four interface orientations on iPad.

**Fix:** Set `TARGETED_DEVICE_FAMILY: "1"` in `project.yml` if iPhone-only. Only flip to `"1,2"` once iPad layouts are actually designed.

### Feature directory sprawl

**Cause:** Developer adds `Helpers/`, `Utilities/`, `Misc/` — all of which become garbage drawers.

**Fix:** Every file goes into one of the 6 top-level directories. Extensions go under `Extensions/`. Shared UI components go under `Views/Components/`. If nothing fits, the file probably belongs in `Services/`.

### `@Observable` macro "not found"

**Cause:** Deployment target set to iOS 16 or lower.

**Fix:** Bump `deploymentTarget.iOS` to `"17.0"` in `project.yml` and regenerate.

## Integration with the pre-archive validator

The `ios-pre-archive-validator` hook reads `project.yml` directly to check:
- `DEVELOPMENT_TEAM` is non-empty
- `CURRENT_PROJECT_VERSION` was bumped
- `TARGETED_DEVICE_FAMILY` matches supported orientations

Keeping this file as the source of truth is what lets the validator work.

## Template reference

See `<plugin-root>/templates/project.yml.template` for the canonical `project.yml` skeleton — copy, rename `YourApp`, fill in your Team ID, and run `xcodegen generate`.
