import Foundation

// MARK: - Response envelopes

struct DataResponse<T: Decodable>: Decodable { let data: T }
struct PaginatedResponse<T: Decodable>: Decodable { let data: [T]; let cursor: String? }
struct EmptyResponse: Decodable {}

// MARK: - Errors

enum APIError: Error {
    case invalidURL
    case httpError(Int, Data)
    case decodingError(Error)
    case unauthorized
}

// MARK: - Client

final class APIClient {
    static let shared = APIClient()
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
    }

    // MARK: Public methods

    func get<T: Decodable>(path: String) async throws -> T {
        try await request(method: "GET", path: path, body: Optional<Int>.none)
    }

    func post<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T {
        try await request(method: "POST", path: path, body: body)
    }

    func post<T: Decodable>(path: String) async throws -> T {
        try await request(method: "POST", path: path, body: Optional<Int>.none)
    }

    func put<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T {
        try await request(method: "PUT", path: path, body: body)
    }

    func delete<T: Decodable>(path: String) async throws -> T {
        try await request(method: "DELETE", path: path, body: Optional<Int>.none)
    }

    // MARK: Multipart upload

    func upload<T: Decodable>(path: String, imageData: Data, filename: String, mimeType: String = "image/jpeg") async throws -> T {
        guard let url = path.asBackendURL else { throw APIError.invalidURL }
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = KeychainService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        return try await send(request: request)
    }

    // MARK: Internal

    private func request<T: Decodable, B: Encodable>(method: String, path: String, body: B?) async throws -> T {
        guard let url = path.asBackendURL else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = KeychainService.shared.getToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            req.httpBody = try encoder.encode(body)
        }
        return try await send(request: req)
    }

    private func send<T: Decodable>(request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.httpError(-1, data)
        }
        if http.statusCode == 401 {
            await AppState.shared.handleUnauthorized()
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(http.statusCode, data)
        }
        // Allow EmptyResponse for 204s with no body
        if T.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! T
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
