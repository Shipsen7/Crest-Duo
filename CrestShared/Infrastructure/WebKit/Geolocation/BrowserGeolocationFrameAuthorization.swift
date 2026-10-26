import Foundation
import WebKit

/// WebKit's document identity and permission, read in a world the page cannot
/// replace. A frame's URL alone does not identify its security origin or grant
/// access through a sandbox or Permissions Policy.
struct BrowserGeolocationFrameAuthorization: Decodable, Equatable {
    // MARK: - Static Variables

    @MainActor private static let contentWorld = WKContentWorld.world(
        name: "io.github.shipsen7.fennavio.geolocation.authorization")
    private static let source = #"""
        if (!globalThis.isSecureContext || globalThis.origin === "null") return null;
        const policy = document.permissionsPolicy || document.featurePolicy;
        if (policy && typeof policy.allowsFeature === "function" && !policy.allowsFeature("geolocation")) return null;
        // WebKit checks document policy before its zero-timeout branch, which
        // does not request permission or start location updates. Its original
        // API remains available here even though the page uses Crest's bridge.
        const allowed = await new Promise(resolve => {
          navigator.geolocation.getCurrentPosition(
            () => resolve(true), error => resolve(error.code === error.TIMEOUT),
            { timeout: 0, maximumAge: 0 }
          );
        });
        if (!allowed) return null;
        globalThis.__crestGeolocationAuthorizationDocument ??= crypto.randomUUID();
        return JSON.stringify({
          origin: globalThis.origin,
          documentIdentifier: globalThis.__crestGeolocationAuthorizationDocument
        });
        """#

    // MARK: - Variables

    private let origin: String
    private let documentIdentifier: String

    // MARK: - Actions - Authorization

    @MainActor
    static func read(in frame: WKFrameInfo?, of webView: WKWebView) async -> Self? {
        guard
            let value = try? await webView.callAsyncJavaScript(
                source, arguments: [:], in: frame, contentWorld: contentWorld),
            let json = value as? String,
            let authorization = try? JSONDecoder().decode(Self.self, from: Data(json.utf8))
        else { return nil }
        return authorization
    }

    func belongs(to expectedOrigin: SiteOrigin) -> Bool {
        guard let url = URL(string: origin), let actualOrigin = SiteOrigin(url: url) else { return false }
        return actualOrigin == expectedOrigin
    }

    /// Check and dispatch in the same isolated-world execution. Checking one
    /// document and then evaluating in the page world could deliver a position
    /// to a replacement document in the same frame.
    @MainActor
    func deliver(_ message: [String: Any], in frame: WKFrameInfo, of webView: WKWebView) async -> Bool {
        let body = """
            const current = await (async () => { \(Self.source) })();
            if (!current) return false;
            const authorization = JSON.parse(current);
            if (authorization.origin !== expectedOrigin || authorization.documentIdentifier !== expectedDocumentIdentifier) return false;
            dispatchEvent(new CustomEvent('__crestGeolocationReply', { detail: JSON.stringify(message) }));
            return true;
            """
        let value = try? await webView.callAsyncJavaScript(
            body,
            arguments: [
                "message": message, "expectedOrigin": origin, "expectedDocumentIdentifier": documentIdentifier,
            ],
            in: frame, contentWorld: Self.contentWorld)
        return value as? Bool == true
    }
}
