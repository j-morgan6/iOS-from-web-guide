import Foundation

/// Test double for APIClientProtocol. Copy into YourAppTests/MockAPIClient.swift.
///
/// Usage:
///     let mock = MockAPIClient()
///     mock.stubbedGetResponse = PaginatedResponse<Bookmark>(data: [...], cursor: nil)
///     let vm = BookmarksViewModel(api: mock)
///     await vm.load()
///     XCTAssertEqual(mock.recordedPaths, ["/bookmarks"])
@MainActor
final class MockAPIClient: APIClientProtocol {
    enum MockError: Error { case noStub }

    var stubbedGetResponse: Any?
    var stubbedPostResponse: Any?
    var stubbedPutResponse: Any?
    var stubbedDeleteResponse: Any?
    var stubbedUploadResponse: Any?
    var stubbedError: Error?
    private(set) var recordedPaths: [String] = []

    private func resolve<T>(_ stub: Any?, path: String) throws -> T {
        recordedPaths.append(path)
        if let error = stubbedError { throw error }
        guard let value = stub as? T else { throw MockError.noStub }
        return value
    }

    func get<T: Decodable>(path: String) async throws -> T {
        try resolve(stubbedGetResponse, path: path)
    }

    func post<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T {
        try resolve(stubbedPostResponse, path: path)
    }

    func post<T: Decodable>(path: String) async throws -> T {
        try resolve(stubbedPostResponse, path: path)
    }

    func put<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T {
        try resolve(stubbedPutResponse, path: path)
    }

    func delete<T: Decodable>(path: String) async throws -> T {
        try resolve(stubbedDeleteResponse, path: path)
    }

    func upload<T: Decodable>(path: String, imageData: Data, filename: String, mimeType: String) async throws -> T {
        try resolve(stubbedUploadResponse, path: path)
    }
}
