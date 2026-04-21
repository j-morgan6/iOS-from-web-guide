import Foundation

enum Configuration {
    static var apiBaseURL: String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              !raw.isEmpty else {
            fatalError("API_BASE_URL not set in Info.plist / xcconfig")
        }
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }
}
