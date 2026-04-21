---
name: swiftui-async-image-with-backend-paths
description: MANDATORY for any AsyncImage rendering a URL from a JSON response. Invoke before writing AsyncImage(url:) anywhere in the View layer.
file_patterns:
  - "**/Views/**/*.swift"
auto_suggest: true
---

# SwiftUI `AsyncImage` with Backend Paths

## RULES — Follow these with no exceptions

1. **Every image URL from the backend goes through `String.asBackendURL`.** Never pass a raw string to `URL(string:)` — if the backend returns `/uploads/abc.jpg`, `URL(string:)` silently returns a URL with no host, and `AsyncImage` displays the placeholder forever with no error.
2. **Create `Extensions/String+BackendURL.swift` on day 1.** Before the first `AsyncImage`. Before the first feature. It's a 10-line extension that prevents 5 duplicate `fullURL(_:)` helpers from growing across the codebase.
3. **Always frame `AsyncImage` explicitly** — `.frame(maxWidth: .infinity).frame(height: X)` or `.aspectRatio(_:, contentMode:).frame(height: X).clipped()`. Otherwise the natural image size bleeds up through the parent VStack (see `swiftui-layout-pitfalls`).
4. **Use the three-argument form with a placeholder.** `AsyncImage(url:) { image in ... } placeholder: { Color.gray.opacity(0.15) }` — so the frame is visually occupied during load.
5. **Never write a per-view `fullURL(_:)` helper.** Use `.asBackendURL`. This rule is enforced by hook H-W-4.

---

## When to invoke

- Writing any `AsyncImage(url:)` call.
- Debugging "the photo never loads, just shows the placeholder forever".
- Setting up a new feature that displays remote images.

## The silent failure

```swift
// Backend responds:
// { "data": { "id": 123, "photo_url": "/uploads/abc.jpg" } }

// ❌ Classic silent failure
AsyncImage(url: URL(string: post.photoURL)) { $0.resizable() }
    placeholder: { ProgressView() }
```

`URL(string: "/uploads/abc.jpg")` returns a URL with no scheme/host. `AsyncImage` dispatches a URLSession load against a hostless URL, gets an opaque failure, falls through to the placeholder, and reports nothing. The user sees a spinning ProgressView forever.

## The fix — `String.asBackendURL`

```swift
// Extensions/String+BackendURL.swift
extension String {
    var asBackendURL: URL? {
        if hasPrefix("http://") || hasPrefix("https://") {
            return URL(string: self)
        }
        return URL(string: Configuration.apiBaseURL + self)
    }
}
```

See `<plugin-root>/templates/String+BackendURL.swift` for the canonical version.

Now:

```swift
// ✅
AsyncImage(url: post.photoURL.asBackendURL) { image in
    image.resizable().aspectRatio(contentMode: .fill)
} placeholder: {
    Color.gray.opacity(0.15)
}
.frame(height: 240)
.clipped()
```

- Relative paths become `https://api.example.com/uploads/abc.jpg`.
- Fully-qualified URLs (S3 signed URLs, CDN URLs) pass through unchanged.
- Nil safety: `.asBackendURL` returns `URL?` which `AsyncImage` accepts directly.

## The day-1 rule

Every iOS project that consumes a web-first backend hits this inside the first 2-3 features. If you don't create `String+BackendURL.swift` on day 1, you'll write 5 different `fullURL(_:)` helpers — one per view file — and then spend a half-day consolidating them.

**Signs you've waited too long:**
- Multiple `fullURL`, `imageURL`, `resolveURL` helpers scattered across views.
- Some views show images; others silently don't.
- A new dev asks "why doesn't this AsyncImage work on the simulator?".

## The full canonical pattern

```swift
struct FeedCardView: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: post.coverImageURL.asBackendURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.15)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipped()
            .cornerRadius(12)

            Text(post.title).font(.headline)
        }
    }
}
```

## Common pitfalls

### "It works on device with full URLs but not simulator with relative URLs"

The simulator and device run identical code. The backend just happens to return different URL shapes in different environments — often signed S3 URLs in prod and `/uploads/...` in dev. `.asBackendURL` handles both.

### Nil URL → AsyncImage shows placeholder forever with no error

That's the exact behavior `.asBackendURL` prevents. If you see this symptom anywhere, grep for `URL(string:` and replace with `.asBackendURL`.

### Hook H-W-4 flags a bare `URL(string:)` in a View file

This is the enforcement path. The hook scans files under `Views/` and flags `URL(string:` calls that don't go through `.asBackendURL`. Fix by adopting the extension.

### The image loads on first render, vanishes on scroll-back

Usually a layout bug, not a URL bug — see `swiftui-layout-pitfalls`. But double-check the URL isn't being recomputed into `nil` somewhere.

### Fully-qualified URLs got "fixed" into broken ones

An earlier, buggier version of the extension prepended the base URL unconditionally:

```swift
// ❌ Don't do this
var asBackendURL: URL? { URL(string: Configuration.apiBaseURL + self) }
```

This turns `https://s3.amazonaws.com/foo.jpg` into `https://api.example.comhttps://s3.amazonaws.com/foo.jpg`. Always check `hasPrefix("http")` first.

## Template reference

See `<plugin-root>/templates/String+BackendURL.swift` — copy into `Extensions/String+BackendURL.swift` on day 1.

## Related skills

- `ios-api-client-foundation` — provides `Configuration.apiBaseURL`.
- `swiftui-layout-pitfalls` — AsyncImage frames and VStack/ScrollView interactions.
- `ios-project-structure` — where `Extensions/` lives in the tree.
