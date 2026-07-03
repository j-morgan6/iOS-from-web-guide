---
name: swiftui-optimistic-ui-pattern
description: MANDATORY for any like, bookmark, follow, favorite, or similar toggle. Use before writing a mutation method on a ViewModel.
---

# SwiftUI Optimistic UI Pattern

## RULES — Follow these with no exceptions

1. **Optimistic update first, API call second.** Mutate the ViewModel's local state synchronously, then fire the API call inside an unawaited `Task { }`. Never `await` the API call before touching the UI — that's perceptible lag.
2. **The API call is fire-and-forget** via `Task { _ = try? await APIClient.shared.post(...) as EmptyResponse }`. The return value is discarded because the UI already reflects the desired state.
3. **Guard against negatives with `max(0, ...)`.** Like count, comment count, follower count — all must be floored at zero. A race or stale state can otherwise produce `-1` likes.
4. **For MVP / beta: do not revert on failure.** The optimistic state stays even if the server rejects. A silent reconcile-on-next-fetch is acceptable. Revert-on-failure is a polish item, not a launch blocker. Document the decision in code or the PR.
5. **Cross-view propagation** (same post displayed in feed + detail) is a separate concern — out of scope for this skill. For MVP, reconcile on the next fetch of each screen.

---

## When to invoke

- Adding a like, bookmark, follow, favorite, or upvote button.
- Adding a "mark as read" or similar binary toggle.
- Adding a reaction picker (extensions of the same pattern).
- Debugging "the tap feels laggy" — almost always because `await` happens before the mutation.

## The canonical toggle

```swift
@MainActor
@Observable
final class FeedViewModel {
    var posts: [Post] = []

    func toggleLike(_ post: Post) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let wasLiked = posts[index].likedByCurrentUser
        posts[index].likedByCurrentUser.toggle()
        posts[index].likeCount = max(0, wasLiked
            ? posts[index].likeCount - 1
            : posts[index].likeCount + 1)

        Task {
            if wasLiked {
                _ = try? await APIClient.shared.delete(path: "/posts/\(post.id)/like") as EmptyResponse
            } else {
                _ = try? await APIClient.shared.post(path: "/posts/\(post.id)/like") as EmptyResponse
            }
        }
    }
}
```

**What happens on tap:**
1. Find the post in the array.
2. Flip `likedByCurrentUser` and adjust `likeCount` immediately.
3. SwiftUI diffs the array, sees the post changed (structural equality — see `swiftui-equatable-hashable-for-diffing`), and re-renders the card. This all happens within a frame.
4. Fire the API call. If it succeeds, great. If it fails, the UI is wrong until the next fetch — accepted MVP trade-off.

## Why the guard

```swift
posts[index].likeCount = max(0, wasLiked ? ... : ...)
```

Without the floor: a stale post with `likeCount: 0` that the user already "liked" elsewhere gets a second unlike tap → count goes to `-1` → the view shows "-1 likes" which looks like a bug report waiting to happen.

## Bookmark / follow — same shape

```swift
func toggleBookmark(_ post: Post) {
    guard let idx = posts.firstIndex(where: { $0.id == post.id }) else { return }
    posts[idx].isBookmarked.toggle()
    Task {
        _ = try? await APIClient.shared.post(path: "/posts/\(post.id)/bookmark") as EmptyResponse
    }
}

func toggleFollow(_ user: User) {
    guard let idx = users.firstIndex(where: { $0.id == user.id }) else { return }
    users[idx].isFollowedByCurrentUser.toggle()
    Task {
        _ = try? await APIClient.shared.post(path: "/users/\(user.id)/follow") as EmptyResponse
    }
}
```

## The View layer

The View just wires the tap:

```swift
Button {
    viewModel.toggleLike(post)
} label: {
    Image(systemName: post.likedByCurrentUser ? "heart.fill" : "heart")
}
.buttonStyle(.borderless)   // critical if inside a NavigationLink — see swiftui-navigation-foundations
```

No `Task` in the View. No `await`. The ViewModel owns all of that.

## Common pitfalls

### Awaiting before mutating

```swift
// ❌
func toggleLike(_ post: Post) async {
    _ = try? await APIClient.shared.post(...) as EmptyResponse
    // ... then mutate
}
```

The user sees 200-800ms of no feedback after the tap. Even on a good network. On 3G it's a full second. Reverse the order.

### Forgetting `max(0, ...)`

Produces negative counts on race conditions. Almost inevitable at scale.

### Attempting revert-on-failure in MVP

```swift
// ❌ At MVP scale — wastes a day getting right
Task {
    do {
        _ = try await APIClient.shared.post(...) as EmptyResponse
    } catch {
        // revert — but what about intermediate states? races? UI loops?
        self.posts[index].likedByCurrentUser = wasLiked
    }
}
```

Do this in 1.1 or later, not 1.0. Write a comment: `// MVP: do not revert on failure — reconcile on next fetch`.

### Relying on the mutation to re-render when `Post` has custom id-only `==`

Doesn't work. See `swiftui-equatable-hashable-for-diffing`. The fix is in the model type, not in the mutation code.

### Using the tapped `post` snapshot instead of `posts[index]`

```swift
// ❌ mutates a local copy, not the array
var mutated = post
mutated.likedByCurrentUser.toggle()
```

`post` is a `let` parameter; the mutation has no effect on the published array. Always go via `posts[index]`.

### Double-tap producing two API calls

Usually acceptable for MVP — the server accepts both. If it becomes a problem, throttle in the ViewModel:

```swift
if isLikePending[post.id] == true { return }
isLikePending[post.id] = true
defer { isLikePending[post.id] = false }
```


## Template reference

No dedicated template — this is a ViewModel pattern. `ios-feature-scaffold` drops the canonical toggle skeleton into generated ViewModels.

## Related skills

- `swiftui-observable-viewmodel-boilerplate` — shape of the ViewModel.
- `swiftui-equatable-hashable-for-diffing` — why structural equality on the model is required for re-renders.
- `ios-api-client-foundation` — the `APIClient.shared.post/delete` calls.
