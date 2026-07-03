import Foundation

/// Abstraction over APIClient so ViewModels can be tested without hitting the
/// network. Inject in the ViewModel initializer:
///
///     init(api: APIClientProtocol = APIClient.shared) { self.api = api }
///
/// Copy into Services/APIClientProtocol.swift. Pair with the MockAPIClient
/// template in your test target.
@MainActor
protocol APIClientProtocol {
    func get<T: Decodable>(path: String) async throws -> T
    func post<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T
    func post<T: Decodable>(path: String) async throws -> T
    func put<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T
    func delete<T: Decodable>(path: String) async throws -> T
    func upload<T: Decodable>(path: String, imageData: Data, filename: String, mimeType: String) async throws -> T
}
