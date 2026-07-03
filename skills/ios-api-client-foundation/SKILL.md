---
name: ios-api-client-foundation
description: MANDATORY for API client and Services work. Use before writing APIClient, any file under Services/, or any networking code.
---

# iOS API Client Foundation

## RULES — Follow these with no exceptions

1. **One singleton: `APIClient.shared`.** Never instantiate `APIClient()` in a view or view model — inject the shared instance or mock it in tests.
2. **Use `async/await` throughout** — no closure-based callback variants, no Combine `Publisher` returns. Every method is `async throws`.
3. **Typed envelopes only.** Every endpoint returns `DataResponse<T>`, `PaginatedResponse<T>`, or `EmptyResponse`. Raw JSON dictionaries are a code smell.
4. **`JSONEncoder` uses `.convertToSnakeCase`** and `JSONDecoder` uses `.convertFromSnakeCase`. Phoenix/Rails/Django all expect snake_case on the wire; camelCase on wire is a bug.
5. **Bearer token injected automatically** from `KeychainService.getToken()` on every authenticated request. The caller never touches `Authorization` headers.
6. **401 is handled centrally** — the client calls `AppState.handleUnauthorized()` on every 401, which logs the user out. Do not add per-call 401 handling.
7. **Base URL comes from `Configuration.apiBaseURL`**, which reads from `Info.plist` (fed by xcconfig). Never hardcode `"http://..."` in a service method.
8. **Multipart uploads use `upload(path:imageData:filename:)`.** Do not hand-roll boundary handling in feature code.

---

## When to invoke

- Creating or editing `APIClient.swift` or `Services/Auth*.swift`.
- Adding a new endpoint method (typically as an `extension APIClient`).
- Debugging a 401 loop or a decode error.
- Porting a web-first backend API to iOS.

## The envelopes

```swift
struct DataResponse<T: Decodable>: Decodable { let data: T }
struct PaginatedResponse<T: Decodable>: Decodable {
    let data: [T]
    let cursor: String?
}
struct EmptyResponse: Decodable {}
```

Every endpoint returns one of these. Example:

```swift
// GET /posts/123 → { "data": { "id": 123, "title": "..." } }
let response: DataResponse<Post> = try await APIClient.shared.get(path: "/posts/123")
let post = response.data
```

## The canonical method signatures

```swift
@MainActor
final class APIClient: APIClientProtocol {
    static let shared = APIClient()

    func get<T: Decodable>(path: String) async throws -> T
    func post<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T
    func post<T: Decodable>(path: String) async throws -> T
    func put<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T
    func delete<T: Decodable>(path: String) async throws -> T
    func upload<T: Decodable>(path: String, imageData: Data, filename: String, mimeType: String = "image/jpeg") async throws -> T
}
```

`APIClientProtocol` (see `templates/APIClientProtocol.swift`) is the seam ViewModels inject for testability; `templates/MockAPIClient.swift` is the matching test double.

## Adding an endpoint

Put new endpoints in a feature-specific extension file, not in the body of `APIClient`:

```swift
// Services/APIClient+Posts.swift
extension APIClient {
    func fetchFeed(cursor: String? = nil) async throws -> PaginatedResponse<Post> {
        let query = cursor.map { "?cursor=\($0)" } ?? ""
        return try await get(path: "/feed\(query)")
    }

    func toggleLike(postId: Int, liked: Bool) async throws -> EmptyResponse {
        if liked {
            return try await delete(path: "/posts/\(postId)/like")
        } else {
            return try await post(path: "/posts/\(postId)/like")
        }
    }
}
```

## Encoder / decoder config

```swift
private let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.keyEncodingStrategy = .convertToSnakeCase
    e.dateEncodingStrategy = .iso8601
    return e
}()

private let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    d.dateDecodingStrategy = .iso8601
    return d
}()
```

## 401 handling

```swift
// Inside the shared request dispatch:
if httpResponse.statusCode == 401 {
    await AppState.shared.handleUnauthorized()
    throw APIError.unauthorized
}
```

`AppState.handleUnauthorized()` clears the keychain token and flips `isAuthenticated = false`. SwiftUI then routes to the login screen automatically.

## Common pitfalls

### Forgetting `convertToSnakeCase` on the encoder

**Symptom:** Phoenix replies with `{"errors": {"first_name": ["can't be blank"]}}` even though you sent `{"firstName": "Joe"}`.

**Fix:** `encoder.keyEncodingStrategy = .convertToSnakeCase`. Same for the decoder.

### Hardcoding the base URL

**Symptom:** Works on simulator, fails on device — or ships prod pointing at localhost.

**Fix:** Read from `Configuration.apiBaseURL`, which pulls from `Info.plist`, which is fed by `Config.xcconfig` (so `Debug` and `Release` can differ).

### Calling `APIClient()` in a test

**Symptom:** Tests hit the real network.

**Fix:** `APIClient.shared` is the only instance. For tests, inject `APIClientProtocol` into view models and use `MockAPIClient` (both provided as templates).

### Manual `Authorization` header in feature code

**Symptom:** A view model pulls the token from Keychain and sets the header on a one-off `URLRequest`.

**Fix:** Move that call through `APIClient`. Bearer injection is centralized — feature code should never touch auth headers.

## Template reference

See `<plugin-root>/templates/APIClient.swift` for the full canonical implementation including envelopes, encoder/decoder, bearer injection, 401 handling, and multipart upload. Copy it into `Services/APIClient.swift` on day 1.
