---
name: swiftui-observable-viewmodel-boilerplate
description: MANDATORY for creating any ViewModel. Invoke before writing any file under ViewModels/ or any class whose name ends in ViewModel.
file_patterns:
  - "**/ViewModels/**/*.swift"
  - "**/*ViewModel.swift"
auto_suggest: true
---

# SwiftUI `@Observable` ViewModel Boilerplate

## RULES — Follow these with no exceptions

1. **Use `@Observable` (Swift Observation, iOS 17+).** Never `@ObservableObject` / `@Published` / `@StateObject` / `@ObservedObject`. This rule is enforced by hook H-W-6.
2. **Every ViewModel is `@MainActor @Observable final class`.** `@MainActor` because views read it on the main thread; `final` because subclassing an Observable breaks tracking.
3. **Views hold ViewModels via `@State`,** not `@StateObject` or `@ObservedObject`. `@State` is the correct property wrapper for `@Observable` reference types since iOS 17.
4. **One ViewModel per screen.** A view doesn't share a ViewModel with its parent — if it needs parent data, pass values in the initializer.
5. **Public mutable properties; no `@Published`.** The macro tracks every stored property automatically. Add explicit `@ObservationIgnored` only on caches or other internal state that shouldn't trigger re-renders.
6. **Async methods do the network work.** The View calls `.task { await viewModel.load() }`, not `onAppear { viewModel.load() }`.
7. **Loading / data / error state is explicit.** Three state properties: `isLoading: Bool`, the data (`items: [T]`), and `errorMessage: String?`. No nil-as-sentinel loading states.

---

## When to invoke

- Creating a new file under `ViewModels/`.
- Converting a pre-iOS-17 `@ObservableObject` ViewModel to `@Observable`.
- Debugging "view doesn't re-render when I mutate the ViewModel" bugs.

## The canonical shape

```swift
import SwiftUI

@MainActor
@Observable
final class FeedViewModel {
    var posts: [Post] = []
    var isLoading = false
    var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: PaginatedResponse<Post> = try await APIClient.shared.get(path: "/feed")
            posts = response.data
        } catch {
            errorMessage = "Couldn't load feed. Pull to refresh."
        }
        isLoading = false
    }

    func toggleLike(_ post: Post) {
        // Optimistic mutation — see swiftui-optimistic-ui-pattern
        guard let idx = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[idx].likedByCurrentUser.toggle()
        Task {
            _ = try? await APIClient.shared.post(path: "/posts/\(post.id)/like") as EmptyResponse
        }
    }
}
```

## The canonical View shape

```swift
struct FeedView: View {
    @State private var viewModel = FeedViewModel()

    var body: some View {
        List(viewModel.posts) { post in
            FeedCardView(post: post)
        }
        .overlay {
            if viewModel.isLoading && viewModel.posts.isEmpty {
                ProgressView()
            }
        }
        .task {
            await viewModel.load()
        }
    }
}
```

## Why `@State` for an `@Observable` class

Before iOS 17, classes used `@StateObject` because `@State` required `Equatable` value semantics. The Observation framework removed that requirement: `@State` now correctly owns the reference, participates in SwiftUI's identity system, and re-renders on any tracked property change.

Using `@StateObject` with `@Observable` **compiles but is wrong** — you get a warning and observation won't trigger.

## Common pitfalls

### Mixing `@Published` and `@Observable`

**Anti-pattern (enforced by hook H-W-6):**

```swift
// ❌ NEVER
@Observable
final class BadViewModel {
    @Published var items: [Item] = []   // @Published has no effect here
}
```

**Fix:** Remove `@Published`. The `@Observable` macro auto-tracks every stored property.

### Using `@ObservedObject` in the View

```swift
// ❌
struct FeedView: View {
    @ObservedObject var viewModel: FeedViewModel  // doesn't own the lifetime
}
```

**Fix:** `@State private var viewModel = FeedViewModel()` if the view owns it, or plain `let viewModel: FeedViewModel` if the parent injects it.

### Not annotating `@MainActor`

**Symptom:** "Property access must be on main actor" crash when a network callback mutates `posts`.

**Fix:** `@MainActor` on the class declaration. All methods now run on main; network work happens inside `async` methods and the `await` hops off and back on.

### `onAppear` instead of `.task`

```swift
// ❌
.onAppear { Task { await viewModel.load() } }
```

**Fix:** `.task { await viewModel.load() }`. `.task` is cancelled when the view disappears; `onAppear` leaks.

### Observation silently broken

If re-renders don't happen:
1. Check the class has `@Observable` — not `@ObservableObject`.
2. Check the view uses `@State` — not `@StateObject`.
3. Check the property is stored (not computed). Observation doesn't track computed properties unless they read other tracked properties during evaluation.
4. Check `deploymentTarget.iOS` is 17+ in `project.yml`.

## Template reference

There's no dedicated template — `@Observable` ViewModels are pure boilerplate. See `ios-feature-scaffold` for the generator that produces Model + ViewModel + View in one pass.

## Related skills

- `swiftui-optimistic-ui-pattern` — for mutation methods.
- `swiftui-equatable-hashable-for-diffing` — so your model types trigger re-renders correctly.
- `ios-api-client-foundation` — for the networking layer called from `async` methods.
