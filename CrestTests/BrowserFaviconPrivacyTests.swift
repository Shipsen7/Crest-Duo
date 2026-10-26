import Foundation
import Network
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserFaviconPrivacyTests: XCTestCase {
    private var navigations: [FaviconPrivacyNavigation] = []

    func testCapturePreservesCookieScopeAndSpaceIsolationAcrossResourceRedirects() async throws {
        let server = try BrowserPrivacyHTTPServer()
        try await server.start()
        defer { server.stop() }
        let pageURL = server.url(host: "parent.localhost", path: "/private/page?secret=query#fragment")
        let webView = makeWebView()
        try await load(server.url(host: "other.localhost", path: "/same-site-cookies"), in: webView)
        try await load(pageURL, in: webView)
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertTrue(cookies.contains { $0.name == "hostOnly" })
        XCTAssertTrue(cookies.contains { $0.name == "domainCookie" })
        XCTAssertTrue(cookies.contains { $0.name == "strictOther" })
        XCTAssertTrue(cookies.contains { $0.name == "laxOther" })
        XCTAssertEqual(cookies.first { $0.name == "hostOnly" }?.domain, "parent.localhost")
        XCTAssertEqual(cookies.first { $0.name == "domainCookie" }?.domain, ".parent.localhost")
        attach(
            cookies.map {
                "\($0.name): domain=\($0.domain), path=\($0.path), secure=\($0.isSecure), properties=\($0.properties ?? [:])"
            }.joined(separator: "\n"), name: "WebKit cookie representation")

        // A second Space has a distinct store even while both pages are alive.
        let otherSpace = makeWebView()
        try await load(server.url(host: "parent.localhost", path: "/other-space"), in: otherSpace)
        try await webView.evaluateJavaScript(
            """
            document.head.innerHTML = '<link rel="manifest" href="/private/manifest-redirect">';
            """)
        let data = await BrowserFaviconCapture.capture(from: webView)
        XCTAssertNotNil(data, "An authenticated manifest and icon must remain discoverable")

        let requests = server.requests.filter {
            ($0.path.contains("manifest") || $0.path.contains("icon")) && $0.headers["sec-fetch-dest"] != "manifest"
        }
        attach(requests.map(\.description).joined(separator: "\n"), name: "Resource wire requests")
        for path in [
            "/private/manifest-redirect", "/private/manifest.json", "/child-icon", "/private/cross-site-icon-redirect",
            "/same-site-icon", "/privateer/icon", "/private/icon-redirect", "/public/icon",
        ] {
            XCTAssertTrue(requests.contains { $0.path == path }, "Missing wire capture for \(path)")
        }
        for request in requests {
            let cookie = request.headers["cookie", default: ""]
            XCTAssertNil(request.headers["referer"], request.description)
            XCTAssertFalse(cookie.contains("spaceB="), request.description)
            XCTAssertFalse(cookie.contains("strictOther="), request.description)
            XCTAssertFalse(cookie.contains("laxOther="), request.description)
            // WebKit permits Secure cookies on trustworthy localhost HTTP.
            // Native fallback requests must never carry them.
            if request.headers["sec-fetch-mode"] == nil {
                XCTAssertFalse(cookie.contains("secureOnly="), request.description)
            }
            if request.host.hasPrefix("child.") {
                XCTAssertFalse(cookie.contains("hostOnly="), request.description)
            }
            if !request.path.hasPrefix("/private/") {
                XCTAssertFalse(cookie.contains("privatePath="), request.description)
            }
        }
        let authenticated = requests.filter { $0.path == "/private/manifest.json" || $0.path == "/public/icon" }
        XCTAssertEqual(authenticated.count, 2)
        XCTAssertTrue(authenticated.allSatisfy { $0.headers["cookie", default: ""].contains("hostOnly=spaceA") })
        withExtendedLifetime(otherSpace) {}
    }

    func testNativeFallbackOmitsURLCredentialsCookiesAndReferrersAcrossRedirects() async throws {
        let server = try BrowserPrivacyHTTPServer()
        try await server.start()
        defer { server.stop() }
        let url = URL(
            string:
                "http://fixture-user:fixture-password@parent.localhost:\(server.port)/credential-icon-redirect#fragment"
        )!
        let data = await BrowserFaviconFallbackLoader.download(url, authorization: { _ in true })
        XCTAssertNotNil(data)
        let denied = await BrowserFaviconFallbackLoader.download(
            server.url(host: "parent.localhost", path: "/auth-icon"), authorization: { _ in true })
        XCTAssertNil(denied)
        let requests = server.requests
        attach(requests.map(\.description).joined(separator: "\n"), name: "Native credentials wire requests")
        XCTAssertTrue(requests.contains { $0.host.hasPrefix("child.") })
        for request in requests {
            XCTAssertNil(request.headers["referer"], request.description)
            XCTAssertNil(request.headers["cookie"], request.description)
            XCTAssertNil(request.headers["authorization"], request.description)
        }
    }

    func testNativeFallbackRespectsWebKitBlockingAndKeepsPublicCDNIcons() async throws {
        let server = try BrowserPrivacyHTTPServer()
        try await server.start()
        defer { server.stop() }
        let identifier = "fennavio-favicon-boundary-\(UUID())"
        let rules = try await BrowserContentRuleListCompiler.compile(
            identifier: identifier,
            source: #"[{"trigger":{"url-filter":"blocked-icon"},"action":{"type":"block"}}]"#)
        let webView = makeWebView()
        webView.configuration.userContentController.add(rules)
        let pageURL = server.url(host: "parent.localhost", path: "/policy/no-referrer")
        try await load(pageURL, in: webView)
        server.overrideResponse = { request in
            if request.path == "/redirect-to-blocked", request.headers["sec-fetch-mode"] == nil {
                return (
                    "302 Found", "Location: http://child.parent.localhost:\(server.port)/blocked-icon\r\n", Data()
                )
            }
            return (
                "200 OK", "Content-Type: image/png\r\n",
                Data(
                    base64Encoded:
                        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
            )
        }
        let authorization: BrowserFaviconResourceLoader.Authorization = { url in
            await BrowserWebKitFaviconAccess.allows(url, in: webView, pageURL: pageURL)
        }
        let blocked = await BrowserFaviconFallbackLoader.download(
            server.url(host: "child.parent.localhost", path: "/blocked-icon"), authorization: authorization)
        let redirected = await BrowserFaviconFallbackLoader.download(
            server.url(host: "parent.localhost", path: "/redirect-to-blocked"), authorization: authorization)
        let allowed = await BrowserFaviconFallbackLoader.download(
            server.url(host: "child.parent.localhost", path: "/public-cdn-icon"), authorization: authorization)
        XCTAssertNil(blocked)
        XCTAssertNil(redirected)
        XCTAssertNotNil(allowed, "A public CDN without CORS headers must remain usable")
        XCTAssertFalse(server.requests.contains { $0.path == "/blocked-icon" })
        XCTAssertTrue(
            server.requests.contains {
                $0.path == "/redirect-to-blocked" && $0.headers["sec-fetch-mode"] == nil
            }, "The native redirect must be checked even when the WebKit probe received a different response")
        for request in server.requests where request.path == "/public-cdn-icon" {
            XCTAssertNil(request.headers["cookie"])
            XCTAssertNil(request.headers["authorization"])
            XCTAssertNil(request.headers["referer"])
        }
        await BrowserContentRuleListCompiler.remove(identifier: identifier)
    }

    func testSidebarFallbackUsesItsSpaceProtectionWithoutALivePage() async throws {
        let server = try BrowserPrivacyHTTPServer()
        try await server.start()
        defer { server.stop() }
        server.overrideResponse = { _ in
            ("200 OK", "Content-Type: image/svg+xml\r\n", Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8))
        }
        let identifier = "fennavio-sidebar-icon-boundary-\(UUID())"
        let rules = try await BrowserContentRuleListCompiler.compile(
            identifier: identifier,
            source: #"[{"trigger":{"url-filter":"favicon[.]ico"},"action":{"type":"block"}}]"#)
        for policy in [ContentBlockingPolicy.balanced, .off] {
            var space = SpaceState.Seed.blank(number: 1)
            space.settings.browsingPreferences.contentBlocking = policy
            let browser = BrowserStore.hostingPages(
                SessionState.Seed(spaces: [space]),
                core: .hostingPages(contentRuleLists: FaviconPrivacyRuleProvider(rules: [rules])))
            let loader = BrowserFaviconFallbackLoader()
            let before = server.requests.count
            let data = await loader.data(
                for: server.url(host: "parent.localhost", path: "/sidebar"), profileID: space.profileID)
            if policy.blocksContent {
                XCTAssertNil(data)
                XCTAssertEqual(server.requests.count, before, "Blocked icons must not start native requests")
            } else {
                XCTAssertNotNil(data, "Turning protection off must retain normal public icons")
            }
            withExtendedLifetime(browser) {}
        }
        await BrowserContentRuleListCompiler.remove(identifier: identifier)
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
    }

    private func load(_ url: URL, in webView: WKWebView) async throws {
        let navigation = FaviconPrivacyNavigation(trustedPort: url.scheme == "https" ? url.port : nil)
        navigations.append(navigation)
        webView.navigationDelegate = navigation
        webView.load(URLRequest(url: url))
        await fulfillment(of: [navigation.finished], timeout: 15)
        if let error = navigation.error { throw error }
    }

    private func attach(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class FaviconPrivacyRuleProvider: BrowserContentRuleListProviding {
    let rules: [WKContentRuleList]

    init(rules: [WKContentRuleList]) { self.rules = rules }

    func balancedRuleLists() async throws -> [WKContentRuleList] { rules }
}

@MainActor
private final class FaviconPrivacyNavigation: NSObject, WKNavigationDelegate {
    let finished = XCTestExpectation(description: "Fixture navigation")
    var error: Error?
    let trustedPort: Int?

    init(trustedPort: Int?) { self.trustedPort = trustedPort }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.host == "parent.localhost",
            challenge.protectionSpace.port == trustedPort,
            let trust = challenge.protectionSpace.serverTrust
        {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.error = error
        finished.fulfill()
    }
}
