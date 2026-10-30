import Foundation
import UIKit
import WebKit

/// Only public WebKit delegate APIs. WebKit retains responsibility for networking,
/// certificate validation, cookies, file uploads and authentication credentials.
@MainActor
final class NativeTabRuntime: NSObject, WKNavigationDelegate, WKUIDelegate {
    let id: UUID
    let webView: WKWebView
    let isPopup: Bool
    private(set) var canRecordDocument = false
    private weak var owner: NativeBrowserSession?
    private var observations: [NSKeyValueObservation] = []
    private var dialog: UIAlertController?
    private var dialogReply: ((String?) -> Void)?

    var secureHost: String? {
        guard canRecordDocument, !webView.isLoading, webView.hasOnlySecureContent,
            webView.serverTrust != nil, let url = webView.url, NativeBrowserAddress.isHTTPS(url)
        else { return nil }
        return url.host
    }

    init(
        tabID: UUID, configuration: WKWebViewConfiguration, owner: NativeBrowserSession,
        ruleList: WKContentRuleList?, isPopup: Bool
    ) {
        id = tabID
        self.owner = owner
        self.isPopup = isPopup
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        // Keep WebKit's provided popup configuration and data store, but do not
        // share the mutable blocker controller with the opener.
        configuration.userContentController = WKUserContentController()
        if let ruleList { configuration.userContentController.add(ruleList) }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observe(\.url)
        observe(\.title)
        observe(\.isLoading)
        observe(\.canGoBack)
        observe(\.canGoForward)
        observe(\.hasOnlySecureContent)
        observe(\.serverTrust)
    }

    private func observe<Value>(_ keyPath: KeyPath<WKWebView, Value>) {
        observations.append(
            webView.observe(keyPath, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.owner?.pageDidChange(self.id, page: self.webView)
                }
            })
    }

    func detach() {
        dismissSiteDialog()
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        owner = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if let target = action.targetFrame, !target.isMainFrame {
            // Local/external-app schemes and HTTP frames are not a back door
            // around the main-document policy. Inline frames stay in WebKit.
            if NativeBrowserAddress.isHTTPS(url) { return .allow }
            let scheme = url.scheme?.lowercased()
            return ["about", "blob", "data"].contains(scheme ?? "") ? .allow : .cancel
        }
        if action.shouldPerformDownload, url.scheme?.lowercased() == "blob",
            action.sourceFrame.securityOrigin.protocol == "https"
        {
            return .download
        }
        guard NativeBrowserAddress.mayLoadAsMainDocument(url) else {
            owner?.pageDidBlockNavigation(tabID: id, page: webView, isPopup: action.targetFrame == nil)
            return .cancel
        }
        return action.shouldPerformDownload ? .download : .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async
        -> WKNavigationResponsePolicy
    {
        guard response.isForMainFrame else { return .allow }
        guard let url = response.response.url, NativeBrowserAddress.mayLoadAsMainDocument(url) else {
            owner?.pageDidBlockNavigation(tabID: id, page: webView, isPopup: false)
            return .cancel
        }
        return response.canShowMIMEType ? .allow : .download
    }

    func webView(
        _ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }

    func webView(
        _ webView: WKWebView, authenticationChallenge challenge: URLAuthenticationChallenge,
        shouldAllowDeprecatedTLS decisionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        decisionHandler(false)
    }

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard action.targetFrame == nil, let url = action.request.url,
            NativeBrowserAddress.mayLoadAsMainDocument(url)
        else {
            owner?.pageDidBlockNavigation(tabID: id, page: webView, isPopup: true)
            return nil
        }
        return owner?.openPopup(from: id, requestURL: url, configuration: configuration)
    }

    func webViewDidClose(_ webView: WKWebView) { owner?.closePopup(id, page: webView) }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        presentSiteDialog(message, frame: frame, isAlert: true) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        presentSiteDialog(message, frame: frame) { completionHandler($0 != nil) }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?, initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        presentSiteDialog(
            prompt, frame: frame, defaultText: defaultText ?? "", acceptsText: true, reply: completionHandler)
    }

    private func presentSiteDialog(
        _ message: String, frame: WKFrameInfo, defaultText: String = "",
        acceptsText: Bool = false, isAlert: Bool = false,
        reply: @escaping (String?) -> Void
    ) {
        guard owner?.allowsInteraction(from: id) == true, dialogReply == nil,
            webView.window?.windowScene?.activationState == .foregroundActive,
            let presenter = webView.window?.rootViewController,
            presenter.presentedViewController == nil, !presenter.isBeingDismissed
        else {
            reply(nil)
            return
        }
        // securityOrigin also identifies inherited blob/about frame origins.
        let origin = frame.securityOrigin
        var address = URLComponents()
        address.scheme = origin.protocol
        address.host = origin.host
        if origin.port > 0 { address.port = origin.port }
        let originLabel =
            address.url.flatMap { NativeBrowserAddress.isHTTPS($0) ? $0.absoluteString : nil }
            ?? "Unverified website"
        let panel = UIAlertController(
            title: "Message from \(originLabel)",
            message: String(message.prefix(2_000)), preferredStyle: .alert)
        if acceptsText { panel.addTextField { $0.text = String(defaultText.prefix(2_000)) } }
        if !isAlert {
            panel.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.finishDialog(nil) })
        }
        panel.addAction(
            UIAlertAction(title: "OK", style: .default) { [weak self, weak panel] _ in
                self?.finishDialog(acceptsText ? (panel?.textFields?.first?.text ?? "") : "")
            })
        dialog = panel
        dialogReply = reply
        presenter.present(panel, animated: false)
    }

    private func finishDialog(_ value: String?) {
        let reply = dialogReply
        dialogReply = nil
        dialog = nil
        reply?(value)
    }

    func dismissSiteDialog() {
        let panel = dialog
        finishDialog(nil)
        panel?.dismiss(animated: false)
    }

    func webView(
        _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        decisionHandler(owner?.allowsInteraction(from: id) == true && origin.protocol == "https" ? .prompt : .deny)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        guard let owner else {
            download.cancel(nil)
            return
        }
        owner.beginDownload(download, tabID: id, page: webView)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        guard let owner else {
            download.cancel(nil)
            return
        }
        owner.beginDownload(download, tabID: id, page: webView)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        canRecordDocument = false
        dismissSiteDialog()
        owner?.pageDidChange(id, page: webView)
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        canRecordDocument = true
        owner?.pageDidChange(id, page: webView)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        owner?.pageDidChange(id, page: webView)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportFailure(error)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        reportFailure(error)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        canRecordDocument = false
        dismissSiteDialog()
        // Never automatically replay a bank/payment form after a process crash.
        owner?.pageDidFail(
            "The page process stopped. Reload to continue; forms were not automatically resent.", tabID: id,
            page: webView)
    }

    private func reportFailure(_ error: Error) {
        canRecordDocument = false
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            owner?.pageDidChange(id, page: webView)
            return
        }
        // Do not surface URLs, authentication tokens or server-provided text
        // from arbitrary NSError descriptions in shared browser chrome.
        owner?.pageDidFail(
            "The page could not be loaded securely. Check the address or your connection and try again.",
            tabID: id, page: webView)
    }
}
