import Foundation

extension String {
    /// Resolves a backend-relative path against Configuration.apiBaseURL.
    /// If the string is already an absolute http(s) URL, returns it as-is.
    /// Use for asset URLs returned from JSON bodies; APIClient handles API path resolution internally.
    var asBackendURL: URL? {
        if hasPrefix("http://") || hasPrefix("https://") {
            return URL(string: self)
        }
        return URL(string: Configuration.apiBaseURL + self)
    }
}
