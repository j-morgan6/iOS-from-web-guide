---
name: ios-feature-scaffold
description: MANDATORY when the user asks to "add a new feature" or similar. Chains API client, ViewModel, and View scaffolding in one pass. User-invoked, not file-pattern-triggered.
file_patterns: []
auto_suggest: true
---

# iOS Feature Scaffold

## RULES — Follow these with no exceptions

1. **One feature = five files.** Model, ViewModel, View, APIClient extension, ViewModel test stub. Generate them all — don't stop after the View.
2. **Every generated file follows the relevant Track A skill.** Model respects `swiftui-equatable-hashable-for-diffing`. ViewModel respects `swiftui-observable-viewmodel-boilerplate`. APIClient extension respects `ios-api-client-foundation`. View respects `swiftui-navigation-foundations` + `swiftui-layout-pitfalls`.
3. **Register navigation destinations at the root `NavigationStack`,** not inside the new feature's View. Hoisting is a hard rule from `swiftui-navigation-foundations`.
4. **Model conforms to `Codable, Hashable, Identifiable, Sendable`** — always all four. Sendable for Swift 6 concurrency, the rest for JSON/SwiftUI.
5. **View has three states: loading, empty, error, data.** Four, actually. Every generated View includes placeholders for all four. Empty-state copy is better than a blank screen.
6. **The ViewModel test stub starts passing with a mocked `APIClient`,** not hitting the network. A failing test skeleton is worse than no test skeleton — leave it green.

---

## When to invoke

- User types or says: "add a new feature called X", "scaffold a Bookmarks feature", "create the Explore screen".
- You're about to create `Views/X/XView.swift` and realize you also need Model + ViewModel + APIClient extension.

This is a **user-invoked** skill (empty `file_patterns`). It's the highest-level orchestration skill — it chains every Track A pattern.

## The generated shape (example: `Bookmarks` feature)

```
Models/Bookmark.swift
ViewModels/BookmarksViewModel.swift
Views/Bookmarks/BookmarksView.swift
Services/APIClient+Bookmarks.swift
YourAppTests/BookmarksViewModelTests.swift
```

Plus one edit to the root `MainView.swift` registering `navigationDestination(for: Bookmark.self)` if the feature is pushable.

## Canonical Model

```swift
// Models/Bookmark.swift
import Foundation

struct Bookmark: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let postId: Int
    let createdAt: Date
    var note: String?
}
```

Conform to all four protocols. No custom `==`. (See `swiftui-equatable-hashable-for-diffing`.)

## Canonical ViewModel

```swift
// ViewModels/BookmarksViewModel.swift
import SwiftUI

@MainActor
@Observable
final class BookmarksViewModel {
    var bookmarks: [Bookmark] = []
    var isLoading = false
    var errorMessage: String?

    private let api: APIClientProtocol

    init(api: APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let response: PaginatedResponse<Bookmark> = try await api.get(path: "/bookmarks")
            bookmarks = response.data
        } catch {
            errorMessage = "Couldn't load bookmarks."
        }
        isLoading = false
    }

    func remove(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        Task {
            _ = try? await api.delete(path: "/bookmarks/\(bookmark.id)") as EmptyResponse
        }
    }
}
```

See `swiftui-observable-viewmodel-boilerplate` and `swiftui-optimistic-ui-pattern`.

## Canonical APIClient extension

```swift
// Services/APIClient+Bookmarks.swift
extension APIClient {
    func fetchBookmarks() async throws -> PaginatedResponse<Bookmark> {
        try await get(path: "/bookmarks")
    }

    func removeBookmark(id: Int) async throws -> EmptyResponse {
        try await delete(path: "/bookmarks/\(id)")
    }
}
```

See `ios-api-client-foundation`.

## Canonical View (four states)

```swift
// Views/Bookmarks/BookmarksView.swift
import SwiftUI

struct BookmarksView: View {
    @State private var viewModel = BookmarksViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.bookmarks.isEmpty {
                ProgressView()
            } else if let message = viewModel.errorMessage {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(message))
            } else if viewModel.bookmarks.isEmpty {
                ContentUnavailableView("No bookmarks yet", systemImage: "bookmark", description: Text("Tap the bookmark icon on any post to save it."))
            } else {
                List {
                    ForEach(viewModel.bookmarks) { bookmark in
                        NavigationLink(value: bookmark) {
                            BookmarkRow(bookmark: bookmark)
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet { viewModel.remove(viewModel.bookmarks[i]) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .containerRelativeFrame(.horizontal, alignment: .leading)
        .navigationTitle("Bookmarks")
        .task { await viewModel.load() }
    }
}
```

See `swiftui-navigation-foundations` and `swiftui-layout-pitfalls`.

## Canonical ViewModel test stub

```swift
// YourAppTests/BookmarksViewModelTests.swift
import XCTest
@testable import YourApp

@MainActor
final class BookmarksViewModelTests: XCTestCase {
    func testLoadPopulatesBookmarks() async {
        let mockAPI = MockAPIClient()
        mockAPI.stubbedGetResponse = PaginatedResponse<Bookmark>(
            data: [Bookmark(id: 1, postId: 42, createdAt: Date(), note: nil)],
            cursor: nil
        )
        let vm = BookmarksViewModel(api: mockAPI)

        await vm.load()

        XCTAssertEqual(vm.bookmarks.count, 1)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }
}
```

The mock starts passing immediately. Real network isn't touched.

## Root navigation destination registration

```swift
// Views/MainView.swift
NavigationStack(path: $router.path) {
    BookmarksView()
        .navigationDestination(for: Bookmark.self) { bookmark in
            BookmarkDetailView(bookmark: bookmark)
        }
        // plus other destinations
}
```

This edit must happen in `MainView.swift`, not anywhere else. Hoisted destinations — see `swiftui-navigation-foundations`.

## Common pitfalls

### Skipping the APIClient extension and calling `URLSession` inline

No. Every network call goes through `APIClient`. If a new endpoint shape is needed, add a method there.

### Skipping the test stub

A ViewModel with no test on merge day becomes a ViewModel with no test ever. Generate the stub even if it only verifies `load()` populates the array.

### Registering `navigationDestination(for:)` inside the new View

The destination never fires if the parent is a lazy container. Always hoist to `MainView` / the root `NavigationStack`.

### Generating a Model without `Sendable`

Swift 6 concurrency will complain the moment you pass the model across an actor boundary. Always all four: `Identifiable, Hashable, Codable, Sendable`.

### Using `@StateObject` in the generated View

Regression to iOS-16-era patterns. Always `@State` for `@Observable` classes.

## Template reference

No single template — this skill composes the Track A templates and patterns. The generated files follow:

- `templates/APIClient.swift` for the client layer.
- `templates/project.yml.template` for where files are rooted in the source tree.

## Related skills

Every Track A skill. This is the orchestrator that invokes them.

- `ios-project-structure` (where files go)
- `ios-api-client-foundation` (APIClient extension)
- `swiftui-observable-viewmodel-boilerplate` (ViewModel shape)
- `swiftui-navigation-foundations` (destination registration)
- `swiftui-layout-pitfalls` (View layout)
- `swiftui-equatable-hashable-for-diffing` (Model conformances)
- `swiftui-async-image-with-backend-paths` (for Views displaying remote images)
- `swiftui-optimistic-ui-pattern` (mutation methods)
