import Foundation

/// One boundary for typed addresses, restored tabs and WebKit navigation.
/// Certificate validation remains entirely with WebKit and the operating system.
enum NativeBrowserAddress {
    static let maximumAddressBytes = 8_192

    static func isHTTPS(_ url: URL) -> Bool {
        guard url.absoluteString.utf8.count <= maximumAddressBytes,
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
            parts.user == nil, parts.password == nil,
            parts.port.map({ (1...65_535).contains($0) }) ?? true
        else { return false }
        return !host.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format
        }
    }

    static func mayLoadAsMainDocument(_ url: URL) -> Bool {
        url.absoluteString == "about:blank" || isHTTPS(url)
    }

    /// Never submit an unsupported explicit scheme or embedded credentials to
    /// the search engine. HTTP is upgraded; a TLS error never triggers fallback.
    static func resolve(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= maximumAddressBytes,
            !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format
            })
        else { return nil }
        if value == "about:blank" { return URL(string: value) }
        if var parts = URLComponents(string: value),
            ["http", "https"].contains(parts.scheme?.lowercased() ?? "")
        {
            parts.scheme = "https"
            guard let url = parts.url, isHTTPS(url) else { return nil }
            return url
        }
        // A scheme-like input is not an ordinary search. In particular this
        // prevents user:password@host and executable URLs leaking into queries.
        if value.contains("://") { return nil }
        if !value.contains(where: \.isWhitespace),
            value == "localhost" || value.hasPrefix("localhost:") || value.contains(".") || value.hasPrefix("[")
        {
            guard let url = URL(string: "https://\(value)"), isHTTPS(url) else { return nil }
            return url
        }
        if URLComponents(string: value)?.scheme != nil { return nil }
        var search = URLComponents()
        search.scheme = "https"
        search.host = "duckduckgo.com"
        search.path = "/"
        search.queryItems = [URLQueryItem(name: "q", value: value)]
        guard let url = search.url, isHTTPS(url) else { return nil }
        return url
    }
}
