---
name: ios-info-plist-privacy-strings
description: MANDATORY for Info.plist work. Use before adding imports that require user permission (PhotosUI, AVFoundation camera, CoreLocation, ATT, HealthKit, Contacts, EventKit).
---

# iOS Info.plist Privacy Strings

## RULES — Follow these with no exceptions

1. **Every permission-gated framework import requires a matching `NSxxxUsageDescription` string in `Info.plist`.** iOS kills the app on first-use of the API if the string is missing — no prompt, no log, just a hard crash with `TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION`.
2. **Usage strings are user-facing copy.** They must name the app, explain the *why* in one sentence, and never read like placeholder text. App Store review rejects "We need this" or "Permission required".
3. **`ITSAppUsesNonExemptEncryption = false` is always set** for apps that use only HTTPS via URLSession (99% of apps). This pre-answers the App Store Connect export-compliance nag that otherwise appears on every build upload.
4. **Missing privacy strings are caught by `validate_pre_archive.sh` before archive.** Fix them there, not after TestFlight rejects.
5. **When an import is added that triggers a permission, the corresponding key is added to `Info.plist` in the same edit.** Don't wait until crash.

---

## When to invoke

- Adding `import PhotosUI`, `import AVFoundation`, `import CoreLocation`, `import AppTrackingTransparency`, `import Contacts`, `import EventKit`, or `import HealthKit` to a Swift file.
- Editing `Info.plist` directly.
- Preparing for first App Store submission.
- Debugging a first-launch crash on a permission-guarded call.

## The import → key mapping

| Import | Required `Info.plist` key(s) |
|---|---|
| `PhotosUI`, `Photos` | `NSPhotoLibraryUsageDescription`, plus `NSPhotoLibraryAddUsageDescription` if you only *save* |
| `AVFoundation` (camera via `AVCaptureDevice`) | `NSCameraUsageDescription` |
| `AVFoundation` (mic via `AVAudioSession`) | `NSMicrophoneUsageDescription` |
| `CoreLocation` | `NSLocationWhenInUseUsageDescription`; `NSLocationAlwaysAndWhenInUseUsageDescription` if background |
| `AppTrackingTransparency` | `NSUserTrackingUsageDescription` |
| `Contacts` | `NSContactsUsageDescription` |
| `EventKit` (calendar) | `NSCalendarsUsageDescription` |
| `EventKit` (reminders) | `NSRemindersUsageDescription` |
| `HealthKit` | `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` |
| `UserNotifications` | No Info.plist key — request permission via `UNUserNotificationCenter` at runtime |
| `LocalAuthentication` (Face ID) | `NSFaceIDUsageDescription` |
| `Speech` | `NSSpeechRecognitionUsageDescription` |

If you don't see your import here, search Apple's [`Information Property List` reference](https://developer.apple.com/documentation/bundleresources/information_property_list) before guessing.

## Recommended copy templates

Use the app's product name and the *specific feature* that triggers the prompt. iOS shows the string verbatim, so every character counts.

```
NSPhotoLibraryUsageDescription:
  "{AppName} needs photo access to attach images to your {noun}."
  e.g. "Trays needs photo access to attach images to your recipes."

NSCameraUsageDescription:
  "{AppName} uses the camera to take photos of your {noun}."

NSMicrophoneUsageDescription:
  "{AppName} uses the microphone to record {noun}."

NSLocationWhenInUseUsageDescription:
  "{AppName} uses your location to show {noun} near you."

NSUserTrackingUsageDescription:
  "Allow tracking so we can show you more relevant {noun}."
  (ATT copy should be plain — it's also shown in the system prompt.)

NSContactsUsageDescription:
  "{AppName} uses your contacts to find friends already on the app."

NSCalendarsUsageDescription:
  "{AppName} adds your {noun} to the calendar when you opt in."

NSFaceIDUsageDescription:
  "{AppName} uses Face ID to unlock your account."

NSHealthShareUsageDescription:
  "{AppName} reads {metric} from Health to {benefit}."

NSHealthUpdateUsageDescription:
  "{AppName} saves {metric} to Health when you log {activity}."
```

**Bad copy (will be rejected):**
- "Required for app functionality."
- "We need access to your photos."
- "Please allow access."

**Good copy:**
- "Trays needs photo access to attach images to your recipes."
- "Trays uses your location to recommend nearby spots."

## Canonical `Info.plist` snippet

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>

<key>UISupportedInterfaceOrientations</key>
<array>
  <string>UIInterfaceOrientationPortrait</string>
</array>

<key>NSPhotoLibraryUsageDescription</key>
<string>Trays needs photo access to attach images to your recipes.</string>

<key>NSCameraUsageDescription</key>
<string>Trays uses the camera to take photos of your recipes.</string>
```

If you use `project.yml` (recommended), these live under `targets.<app>.info.properties` instead of a freestanding `Info.plist`.

## Export compliance — `ITSAppUsesNonExemptEncryption`

Set this key **once** and forget it. HTTPS via `URLSession` is exempt per Apple's export-compliance rules, and the overwhelming majority of apps qualify as "uses only standard encryption."

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

Without this key, App Store Connect shows a "Missing Compliance" banner on every build and blocks TestFlight distribution until you answer the questionnaire manually.

Only set to `true` (and file annual self-classification) if you ship custom cryptography — rare.

## Auto-add behavior

When a skill-aware edit adds, e.g., `import PhotosUI` to a Swift file, the corresponding `NSPhotoLibraryUsageDescription` should be added to `Info.plist` in the same turn. The workflow:

1. Grep the source tree for the import regex (e.g. `import[[:space:]]+PhotosUI`).
2. Grep `Info.plist` for the matching key.
3. If absent, insert with a sensible copy template (see above). Ask the user to edit the copy to match their app's specifics.

The validator (see below) will catch anything missed.

## How `validate_pre_archive.sh` enforces presence

`scripts/validate_pre_archive.sh` runs as part of the pre-archive hook. Check 4 walks the following pairs:

```
import[[:space:]]+PhotosUI          → NSPhotoLibraryUsageDescription
AVCaptureDevice                     → NSCameraUsageDescription
import[[:space:]]+CoreLocation      → NSLocationWhenInUseUsageDescription
import[[:space:]]+AppTrackingTransparency → NSUserTrackingUsageDescription
```

If any `.swift` file matches the import regex and the key is declared in neither the project's `Info.plist` (found anywhere in the tree) nor `project.yml`'s `info.properties`, validation fails with exit code 2 and prints the key name to add. To bypass in rare legitimate cases:

```bash
IOS_FROM_WEB_SKIP_VALIDATOR=1 xcodebuild archive ...
```

Document the reason in the commit message when you do.

## Common pitfalls

### "App crashes on first camera tap, no crash log"

Cause: missing `NSCameraUsageDescription`. iOS kills the process synchronously with a TCC violation that doesn't always surface in Xcode's console.

**Fix:** add the key. Run `validate_pre_archive.sh` locally to catch it pre-flight.

### "TestFlight shows Missing Compliance"

Cause: `ITSAppUsesNonExemptEncryption` absent.

**Fix:** set `<false/>`. Re-archive and re-upload.

### "We added the key but it still crashes"

Cause: The key is in a `Info.plist` that's not the one bundled into the app — e.g., you edited `YourApp/Info.plist` but the target is configured to use `Info-Release.plist`. With XcodeGen, the `info.path` in `project.yml` is the source of truth.

**Fix:** confirm which plist the target uses (`xcodebuild -showBuildSettings | grep INFOPLIST_FILE`).

### "Location prompt shows wrong string"

Cause: added `NSLocationAlwaysAndWhenInUseUsageDescription` but are calling `requestWhenInUseAuthorization()` — iOS shows the `WhenInUse` string for that API. You need *both* strings if you ever upgrade to Always.

**Fix:** add both keys with distinct copy. `WhenInUse` is always required as the prerequisite.

## Template reference

There is no standalone privacy-strings template — the canonical `project.yml.template` under `<plugin-root>/templates/project.yml.template` already includes `ITSAppUsesNonExemptEncryption: false` and placeholder `NSPhotoLibraryUsageDescription` / `NSCameraUsageDescription` entries. Fill in per-app copy as you add the relevant imports.

## Related skills

- `ios-project-structure` — where `Info.plist` and `project.yml` live in the opinionated layout.
- `ios-app-icon-asset-prep` — the other common "blocks archive" gotcha.
