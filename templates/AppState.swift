import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    static let shared = AppState()
    var isAuthenticated: Bool = false
    var currentUser: User? = nil

    private init() {
        self.isAuthenticated = KeychainService.shared.getToken() != nil
    }

    func handleUnauthorized() {
        KeychainService.shared.deleteToken()
        isAuthenticated = false
        currentUser = nil
    }

    func signedIn(user: User, token: String) {
        KeychainService.shared.save(token: token)
        currentUser = user
        isAuthenticated = true
    }
}

struct User: Codable, Hashable, Sendable {
    let id: Int
    let username: String
}
