---
name: ios-auth-keychain-storage
description: MANDATORY for auth token storage. Use before writing any code that stores, reads, or deletes authentication credentials.
---

# iOS Auth & Keychain Storage

## RULES — Follow these with no exceptions

1. **Auth tokens go in Keychain. Never UserDefaults.** UserDefaults is unencrypted plist-on-disk — a device compromise exposes every token. This rule is enforced by the blocking `userdefaults-token` hook.
2. **Use `kSecClassGenericPassword`** with a fixed `kSecAttrAccount` value (e.g. `"auth_token"`). One token per account name.
3. **Set `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock`** — the token is readable when the app is backgrounded, but not before first unlock after reboot. Required for background refresh to work.
4. **Provide exactly three public methods:** `save(token:)`, `getToken() -> String?`, `deleteToken()`. No variants, no convenience overloads.
5. **Treat all Keychain errors as "no token present"** — if `SecItemCopyMatching` returns non-zero, return `nil` from `getToken()`. Don't throw — the only sane response to a broken Keychain is to force re-login.
6. **Never log tokens.** Not in `print`, not in error messages, not in analytics. Even in debug builds.
7. **The `APIClient` calls `KeychainService.shared.getToken()` on every request.** Feature code should never read the token directly.

---

## When to invoke

- Creating `Services/KeychainService.swift`.
- Adding login / logout / token-refresh flows.
- Debugging an auth loop (usually a sign the token isn't persisting across launches).

## Why not UserDefaults

UserDefaults writes to `~/Library/Preferences/<bundle-id>.plist` as unencrypted XML. Anyone with filesystem access (jailbroken device, backup extraction, or `xcrun simctl` on simulator) reads tokens in plain text.

Keychain:
- Encrypted at rest with the device's Secure Enclave.
- Scoped per-app by default.
- Survives app reinstall if you opt in (don't — you want a fresh login after reinstall).
- Accessible from extensions if you share the Keychain access group.

## The canonical API

```swift
final class KeychainService {
    static let shared = KeychainService()
    private let account = "auth_token"
    private let service = Bundle.main.bundleIdentifier ?? "com.yourcompany.yourapp"

    func save(token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)  // remove any existing
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    func getToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

See `<plugin-root>/templates/KeychainService.swift` for the canonical drop-in implementation.

## Typical login flow

```swift
func login(email: String, password: String) async throws {
    let response: DataResponse<LoginResponse> = try await APIClient.shared.post(
        path: "/auth/login",
        body: LoginRequest(email: email, password: password)
    )
    KeychainService.shared.save(token: response.data.token)
    AppState.shared.isAuthenticated = true
}

func logout() {
    KeychainService.shared.deleteToken()
    AppState.shared.isAuthenticated = false
}
```

## Common pitfalls

### Using UserDefaults "just to get things working"

**Anti-pattern (blocked by the `userdefaults-token` hook):**

```swift
// ❌ NEVER
UserDefaults.standard.set(token, forKey: "auth_token")
```

**Fix:** `KeychainService.shared.save(token:)`. There is no scenario where UserDefaults for a token is correct. The `userdefaults-token` hook rejects any Write/Edit that stores `token`, `password`, `secret`, `apiKey`, `bearer`, or `credential` values in UserDefaults.

### Using `kSecAttrAccessibleAlways` or `WhenUnlocked`

- `kSecAttrAccessibleAlways` is **deprecated** and downgrades security.
- `kSecAttrAccessibleWhenUnlocked` breaks background requests because the token is unreadable while the device is locked.

**Fix:** `kSecAttrAccessibleAfterFirstUnlock`.

### Leaving stale entries on login

**Symptom:** Logging in with a new account returns the old account's token.

**Cause:** `SecItemAdd` fails silently with `errSecDuplicateItem` if the account already exists.

**Fix:** Always `SecItemDelete` before `SecItemAdd` (as shown above), or use `SecItemUpdate`.

### Logging the token in error messages

```swift
// ❌
print("Auth failed with token: \(token)")
```

**Fix:** Log token presence (`token == nil`), not the token itself.

## Template reference

See `<plugin-root>/templates/KeychainService.swift` for the canonical implementation. Copy into `Services/KeychainService.swift` on day 1 — before writing any auth flow.
