---
name: swiftui-equatable-hashable-for-diffing
description: MANDATORY for model structs used in SwiftUI views, especially with NavigationLink(value:) or @Observable arrays. Invoke before writing custom Equatable or Hashable conformances on model types.
file_patterns:
  - "**/Models/**/*.swift"
auto_suggest: true
---

# SwiftUI Equatable/Hashable for Correct Diffing

## RULES — Follow these with no exceptions

1. **Let Swift auto-synthesize `Equatable` and `Hashable` on model structs** by declaring the conformance without an explicit implementation. Auto-synthesis gives you **structural equality** — the behavior SwiftUI's diffing actually needs.
2. **Never write a custom `==` that only compares `id`** on a model type used by SwiftUI. This silently breaks re-renders when non-id fields mutate.
3. **All nested types must also be `Hashable`.** If `Post` contains `[Ingredient]`, then `Ingredient` must be `Hashable` too — otherwise synthesis fails and you're tempted to write a custom bad `==`.
4. **If you genuinely need identity-only equality** (e.g., for `NavigationPath` routing keys), wrap the id in a dedicated `Identifiable`-only type and use *that* as the navigation value. Don't pollute the model itself.
5. **Don't mix `struct`-level `Equatable` with an `extension` override.** If you write `extension Post: Equatable { static func == ... }`, you've turned off auto-synthesis and every future field you add is quietly excluded from equality.

---

## When to invoke

- Creating a new model struct.
- Adding navigation that uses the model as a `NavigationLink(value:)`.
- Debugging "I mutated the post but the view didn't re-render".
- Adding fields to an existing model and noticing stale UI.

## The Trays bookmark bug

The real bug this skill prevents:

```swift
// ❌ The subtle bug
struct Post: Identifiable, Hashable {
    let id: Int
    var title: String
    var isBookmarked: Bool

    static func == (lhs: Post, rhs: Post) -> Bool {
        lhs.id == rhs.id   // id-only equality — BAD
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
```

`toggleBookmark` mutates `isBookmarked`, but since the replaced post compares `==` to the old one (same id), SwiftUI's diffing decides the view didn't change and skips re-render. The server updates; the UI stays stale. Force-quit and relaunch shows the correct state.

**The fix: auto-synthesize.**

```swift
// ✅
struct Post: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    var title: String
    var isBookmarked: Bool
    var author: User           // User must be Hashable
    var ingredients: [Ingredient]  // Ingredient must be Hashable
}
```

No custom `==`. Swift synthesizes structural equality from all stored properties. `isBookmarked` changes → posts are unequal → SwiftUI re-renders.

## Making nested types Hashable

```swift
struct User: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    var username: String
    var avatarURL: String?
}

struct Ingredient: Hashable, Codable, Sendable {
    let name: String
    let amount: String
}
```

If any nested type is not `Hashable`, synthesis silently fails and Xcode surfaces a compile error like *"Type 'Post' does not conform to protocol 'Hashable'"*. Fix the leaf type, not the parent.

## When you genuinely need id-only equality

Sometimes `NavigationPath` or `.id(...)` really does want identity-only comparison. Don't override the model's `==` — introduce a wrapper:

```swift
struct PostRoute: Hashable, Identifiable {
    let id: Int
}

// Navigation value
NavigationLink(value: PostRoute(id: post.id)) { FeedCardView(post: post) }

// Root destination
.navigationDestination(for: PostRoute.self) { route in
    PostDetailLoader(postId: route.id)  // fetches the post
}
```

Now `Post` remains structurally equatable (so lists re-render correctly) and the navigation layer uses a separate identity-only type.

## How SwiftUI uses `==`

When `@Observable` ViewModel's array mutates, SwiftUI diffs the old and new values of properties read during `body`. For each element it checks `==`. If `==` says "equal," the child view is not re-rendered. Custom id-only `==` therefore produces stale UI for every post field that isn't the id.

## Common pitfalls

### Partial auto-synthesis after a field addition

```swift
// Week 1:
struct Post: Hashable { let id: Int; var title: String }
// Week 2: added `var likeCount: Int`
// ✅ Auto-synthesis picks up the new field automatically.
```

This only works because there's **no custom `==`**. If there were one, `likeCount` would be silently excluded.

### Forgotten `Hashable` on an array element type

**Symptom:** `error: type 'Post' does not conform to protocol 'Hashable'`.

**Cause:** Some nested type (often added months later, like `var tags: [Tag]`) is missing `Hashable`.

**Fix:** Add `Hashable` to the leaf type. Don't override `==` on the parent to paper over it.

### `NavigationLink(value:)` fails with "not Hashable"

Same root cause. Either declare the type `Hashable` (auto-synthesis) or wrap the id in a `PostRoute`-style struct.

### `[Post]` in `@Observable` doesn't trigger updates

Check you aren't reassigning the whole array to a functionally-equal value via a custom `==`. Auto-synthesis on structural equality is what makes `posts[idx] = updated` trigger a view refresh.

## Template reference

No dedicated template — the rule is structural: declare `Hashable` on the type and don't write custom `==`.

## Related skills

- `swiftui-navigation-foundations` — navigation values must be Hashable.
- `swiftui-observable-viewmodel-boilerplate` — view models hold arrays of these models.
- `swiftui-optimistic-ui-pattern` — mutation patterns rely on structural equality to trigger re-renders.
