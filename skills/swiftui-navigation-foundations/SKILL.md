---
name: swiftui-navigation-foundations
description: MANDATORY for any screen with navigation. Invoke before writing a NavigationStack, NavigationLink, or navigationDestination.
file_patterns:
  - "**/Views/**/*.swift"
  - "**/MainView.swift"
auto_suggest: true
---

# SwiftUI Navigation Foundations

## RULES — Follow these with no exceptions

1. **Use `NavigationStack` + `navigationDestination(for:)`** — iOS 16+ API. Never `NavigationView` (deprecated) or `NavigationLink(destination:)` (destination-first style is effectively deprecated too).
2. **Prefer `NavigationLink(value:)`** with a typed value and a hoisted `navigationDestination(for: T.self)`. The value must be `Hashable`.
3. **Hoist all `navigationDestination(for:)` modifiers to the root view that owns the `NavigationStack`.** Placing them inside lazy containers (`TabView(.page)`, `LazyVStack`, `LazyVGrid`) silently fails to register them.
4. **For nested tap targets inside a `NavigationLink`, use `.buttonStyle(.borderless)` — NOT `.plain`.** `.borderless` claims tap ownership (so inner Buttons fire); `.plain` only removes visual styling and inner taps still bubble to the outer link. This rule is enforced by hook H-W-3.
5. **Programmatic navigation uses `NavigationPath`** bound via `NavigationStack(path: $router.path)`. Deep links / push-from-anywhere flows append to the path.
6. **One `NavigationStack` per tab.** Don't nest NavigationStacks inside NavigationStacks — state behaves oddly.

---

## When to invoke

- Creating a screen that pushes another screen.
- Setting up `MainView` / the root tab container.
- Adding a deep-link handler.
- Debugging "the tap goes to the wrong place" or "the destination never pushes".

## The canonical pattern

```swift
// Root view — owns the NavigationStack AND every navigationDestination
struct MainView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            FeedView()
                .navigationDestination(for: Post.self) { post in
                    PostDetailView(post: post)
                }
                .navigationDestination(for: User.self) { user in
                    ProfileView(user: user)
                }
        }
    }
}

// Feed — pushes via value, not destination
struct FeedView: View {
    @State private var viewModel = FeedViewModel()

    var body: some View {
        List(viewModel.posts) { post in
            NavigationLink(value: post) {
                FeedCardView(post: post)
            }
        }
    }
}
```

Note `navigationDestination(for: Post.self)` lives on the root, not inside `FeedView`. The `NavigationLink(value: post)` hands the `Post` up the tree; the root resolves which view to push.

## The `.borderless` vs `.plain` trap

Suppose a feed card contains a like button:

```swift
NavigationLink(value: post) {
    VStack {
        Text(post.title)
        Button("Like") { viewModel.toggleLike(post) }  // want this to fire
    }
}
```

Without any `buttonStyle`, the tap on "Like" bubbles up to the NavigationLink and pushes the detail view.

```swift
// ❌ DOES NOT WORK — .plain removes styling but inner tap still bubbles
Button("Like") { viewModel.toggleLike(post) }
    .buttonStyle(.plain)

// ✅ WORKS — .borderless claims tap ownership
Button("Like") { viewModel.toggleLike(post) }
    .buttonStyle(.borderless)
```

This bit the Trays project. It compiles, it looks right, and it's wrong. Hook H-W-3 flags `.buttonStyle(.plain)` inside a `NavigationLink` subtree.

## Programmatic navigation

```swift
@MainActor
@Observable
final class Router {
    var path = NavigationPath()

    func openPost(_ post: Post) { path.append(post) }
    func openProfile(_ user: User) { path.append(user) }
    func popToRoot() { path = NavigationPath() }
}

struct MainView: View {
    @State private var router = Router()

    var body: some View {
        NavigationStack(path: $router.path) {
            FeedView()
                .environment(router)
                .navigationDestination(for: Post.self) { PostDetailView(post: $0) }
                .navigationDestination(for: User.self) { ProfileView(user: $0) }
        }
    }
}
```

Now any descendant can call `@Environment(Router.self) var router` and `router.openPost(post)` to push.

## Common pitfalls

### Destination inside a `TabView(.page)` silently does nothing

```swift
// ❌
TabView {
    ForEach(feeds) { feed in
        FeedView(feed: feed)
            .navigationDestination(for: Post.self) { ... }  // never registers
    }
}
.tabViewStyle(.page)
```

**Fix:** Hoist the `.navigationDestination` to the root outside the TabView.

### Nested NavigationLinks "don't work"

They do — if the inner one uses `.buttonStyle(.borderless)`:

```swift
NavigationLink(value: post) {
    VStack {
        Text(post.title)
        NavigationLink(value: post.author) { Text(post.author.name) }
            .buttonStyle(.borderless)
    }
}
```

### Still using `NavigationLink(destination:)`

```swift
// ❌ Old style — loses state on re-render, can't be deep-linked
NavigationLink(destination: PostDetailView(post: post)) {
    FeedCardView(post: post)
}
```

**Fix:** Use `NavigationLink(value: post)` with a hoisted `navigationDestination(for: Post.self)`.

### Destination value isn't `Hashable`

**Symptom:** Compiler error "Type 'Post' does not conform to 'Hashable'".

**Fix:** Declare `Post: Hashable`. Auto-synthesis requires all stored properties to be Hashable. See `swiftui-equatable-hashable-for-diffing`.

## Template reference

No dedicated template — the canonical shape lives in `MainView.swift` generated by `ios-feature-scaffold`.

## Related skills

- `swiftui-equatable-hashable-for-diffing` — the Hashable requirement for navigation values.
- `ios-feature-scaffold` — registers new navigation destinations at the root NavigationStack automatically.
