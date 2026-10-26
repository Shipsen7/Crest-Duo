import Foundation
import WebKit

/// Authorizes the credential-free native fallback through WebKit itself. A
/// no-CORS probe distinguishes a public CDN from a load WebKit blocked, without
/// duplicating WebKit's filter language or exposing the browsing session.
@MainActor
final class BrowserWebKitFaviconAccess: NSObject, WKNavigationDelegate {
    // MARK: - Types

    private struct Binding {
        weak var value: WebKitEngineBinding?
    }

    // MARK: - Static Variables

    private static var bindings: [Binding] = []
    private static let source = #"""
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 5000);
        try {
          const response = await fetch(resourceURL, {
            mode: "no-cors", credentials: "omit", referrerPolicy: "no-referrer",
            cache: "no-store", signal: controller.signal
          });
          if (response.body) await response.body.cancel();
          return true;
        } catch (_) {
          return false;
        } finally {
          clearTimeout(timeout);
          controller.abort();
        }
        """#

    // MARK: - Variables

    private let webView: WKWebView
    private var navigation: CheckedContinuation<Bool, Never>?
    private var timeout: Task<Void, Never>?

    // MARK: - Initializers

    private init(ruleLists: [WKContentRuleList]) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.inactiveSchedulingPolicy = .none
        for ruleList in ruleLists { configuration.userContentController.add(ruleList) }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    // MARK: - Actions - Binding

    static func register(_ binding: WebKitEngineBinding) {
        bindings.removeAll { $0.value == nil || $0.value === binding }
        bindings.append(Binding(value: binding))
    }

    // MARK: - Actions - Downloads

    static func download(_ iconURL: URL, for pageURL: URL, profileID: UUID) async -> Data? {
        // A sidebar may request an icon before its tab has a live page. Use the
        // owning Space's current rules in a transient, cookie-free document.
        for entry in bindings.reversed() {
            guard let binding = entry.value, let core = binding.core,
                let space = core.state.workspaces.values.lazy.flatMap({ $0.spaces.models })
                    .first(where: { $0.profileID == profileID })
            else { continue }
            let policy = space.settings.browsingPreferences.contentBlocking
            if policy.blocksContent {
                await binding.contentRules.prepare()
                guard binding.contentRules.balancedRuleLists != nil else { return nil }
            }
            let access = BrowserWebKitFaviconAccess(ruleLists: binding.contentRules.ruleLists(for: policy))
            guard await access.load(pageURL), let documentURL = access.webView.url,
                SiteOrigin(url: documentURL) == SiteOrigin(url: pageURL)
            else { return nil }
            defer { access.webView.stopLoading() }
            return await BrowserFaviconFallbackLoader.download(
                iconURL,
                authorization: { resourceURL in
                    await allows(resourceURL, in: access.webView, pageURL: documentURL)
                })
        }
        // An unknown/deleted profile has no authorization to start a request.
        return nil
    }

    static func allows(_ url: URL, in webView: WKWebView, pageURL: URL) async -> Bool {
        guard !Task.isCancelled, webView.url == pageURL else { return false }
        let value = try? await webView.callAsyncJavaScript(
            source, arguments: ["resourceURL": url.absoluteString], in: nil, contentWorld: .defaultClient)
        return value as? Bool == true && !Task.isCancelled && webView.url == pageURL
    }

    private func load(_ pageURL: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            navigation = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                self?.finish(false)
            }
            webView.loadSimulatedRequest(
                URLRequest(url: pageURL),
                responseHTML: "<html><head><meta name='referrer' content='no-referrer'></head></html>")
        }
    }

    private func finish(_ loaded: Bool) {
        timeout?.cancel()
        timeout = nil
        navigation?.resume(returning: loaded)
        navigation = nil
    }

    // MARK: - Actions - Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish(false) }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        finish(false)
    }
}
