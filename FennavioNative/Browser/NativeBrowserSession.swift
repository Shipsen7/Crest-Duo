import Foundation
import Observation
import UIKit
import WebKit

/// The native preview's own session owner. This target intentionally does not
/// import CrestCore, CrestShared, or the existing browser's storage adapters.
@MainActor
@Observable
final class NativeBrowserSession {
    private(set) var state: NativeBrowserState
    private(set) var privateTabs: [NativeBrowserTab]
    private(set) var selectedPrivateTabID: UUID
    private(set) var isPrivate = false
    private(set) var pageRevision = 0
    private(set) var statusMessage: String?
    private(set) var completedDownloads: [NativeCompletedDownload] = []
    private(set) var contentBlockingEnabled: Bool

    @ObservationIgnored private let storage: NativeBrowserStorage
    @ObservationIgnored private var privateDataStore = WKWebsiteDataStore.nonPersistent()
    @ObservationIgnored private var runtimes: [UUID: NativeTabRuntime] = [:]
    @ObservationIgnored private let downloadCenter = NativeDownloadCenter()
    @ObservationIgnored private let contentRuleList: WKContentRuleList?

    init(storage: NativeBrowserStorage? = nil, contentRuleList: WKContentRuleList? = nil) throws {
        let storage = try storage ?? NativeBrowserStorage()
        self.storage = storage
        self.contentRuleList = contentRuleList
        contentBlockingEnabled = contentRuleList != nil
        state = try storage.load()
        let first = NativeBrowserTab.blank()
        privateTabs = [first]
        selectedPrivateTabID = first.id
        downloadCenter.owner = self
        cleanupDeletedDataStores()
    }

    var spaces: [NativeBrowserSpace] { state.spaces }
    var selectedSpaceID: UUID { state.selectedSpaceID }
    var selectedSpaceName: String { isPrivate ? "Private" : (state.selectedSpace?.name ?? "Space") }
    var tabs: [NativeBrowserTab] { isPrivate ? privateTabs : (state.selectedSpace?.tabs ?? []) }
    var selectedTabID: UUID {
        isPrivate ? selectedPrivateTabID : (state.selectedSpace?.selectedTabID ?? state.spaces[0].selectedTabID)
    }
    var selectedTab: NativeBrowserTab? { tabs.first { $0.id == selectedTabID } }
    var canGoBack: Bool {
        _ = pageRevision
        return runtimes[selectedTabID]?.webView.canGoBack ?? false
    }
    var canGoForward: Bool {
        _ = pageRevision
        return runtimes[selectedTabID]?.webView.canGoForward ?? false
    }
    var isLoading: Bool {
        _ = pageRevision
        return runtimes[selectedTabID]?.webView.isLoading ?? false
    }

    var hasContentProtection: Bool { contentRuleList != nil }

    var visibleDownloads: [NativeCompletedDownload] {
        completedDownloads.filter { $0.isPrivate == isPrivate }
    }

    var currentHost: String? {
        _ = pageRevision
        guard let url = runtimes[selectedTabID]?.webView.url,
            NativeBrowserAddress.mayLoadAsMainDocument(url)
        else { return nil }
        return url.host
    }

    func webView(for tabID: UUID) -> WKWebView? {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return nil }
        if let existing = runtimes[tabID] { return existing.webView }
        // Safari-like tab groups share normal cookies. Private browsing always
        // stays in a separate, nonpersistent store and is never saved.
        let websiteDataStore = isPrivate ? privateDataStore : WKWebsiteDataStore.default()
        let runtime = NativeTabRuntime(
            tab: tab, dataStore: websiteDataStore, owner: self,
            ruleList: contentBlockingEnabled ? contentRuleList : nil)
        runtimes[tabID] = runtime
        return runtime.webView
    }

    func switchToSpace(_ id: UUID) {
        persist { try $0.selectSpace(id) }
        isPrivate = false
    }

    func switchToPrivate() {
        isPrivate = true
    }

    func endPrivateSession() {
        let ids = Set(privateTabs.map(\.id))
        discardRuntimes(for: ids)
        downloadCenter.cancelPrivate()
        for file in completedDownloads where file.isPrivate {
            try? FileManager.default.removeItem(at: file.fileURL.deletingLastPathComponent())
        }
        completedDownloads.removeAll { $0.isPrivate }
        privateDataStore = .nonPersistent()
        let first = NativeBrowserTab.blank()
        privateTabs = [first]
        selectedPrivateTabID = first.id
        isPrivate = false
        pageRevision &+= 1
    }

    func createSpace(name: String) {
        persist { _ = $0.createSpace(name: name) }
        isPrivate = false
    }

    func renameSpace(_ id: UUID, to name: String) {
        persist { try $0.renameSpace(id, to: name) }
    }

    func reorderSpaces(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        persist { try $0.reorderSpaces(fromOffsets: offsets, toOffset: destination) }
    }

    func reorderTabs(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard !isPrivate else { return }
        let spaceID = state.selectedSpaceID
        persist { try $0.reorderTabs(in: spaceID, fromOffsets: offsets, toOffset: destination) }
    }

    /// Groups share the regular WebKit profile, so a moved page keeps its
    /// live form contents and history. This operation never moves private tabs.
    func moveTab(_ id: UUID, to destinationID: UUID) {
        guard !isPrivate else { return }
        let sourceID = state.selectedSpaceID
        guard sourceID != destinationID else { return }
        persist { try $0.moveTab(id, from: sourceID, to: destinationID) }
        guard state.spaces.first(where: { $0.id == destinationID })?.tabs.contains(where: { $0.id == id }) == true
        else { return }
        statusMessage = nil
        pageRevision &+= 1
    }

    func deleteSpace(_ id: UUID) {
        guard let space = state.spaces.first(where: { $0.id == id }) else { return }
        let previouslyPending = state.pendingDataStoreDeletions
        persist { try $0.deleteSpace(id) }
        guard !previouslyPending.contains(id), state.pendingDataStoreDeletions.contains(id) else { return }
        discardRuntimes(for: Set(space.tabs.map(\.id)))
        isPrivate = false
        cleanupDeletedDataStores()
    }

    func newTab() {
        if isPrivate {
            let tab = NativeBrowserTab.blank()
            privateTabs.append(tab)
            selectedPrivateTabID = tab.id
        } else {
            let spaceID = state.selectedSpaceID
            persist { _ = try $0.newTab(in: spaceID) }
        }
    }

    func selectTab(_ id: UUID) {
        if isPrivate {
            if privateTabs.contains(where: { $0.id == id }) { selectedPrivateTabID = id }
        } else {
            let spaceID = state.selectedSpaceID
            persist { try $0.selectTab(id, in: spaceID) }
        }
    }

    func closeTab(_ id: UUID) {
        if isPrivate {
            guard let index = privateTabs.firstIndex(where: { $0.id == id }) else { return }
            privateTabs.remove(at: index)
            if privateTabs.isEmpty { privateTabs.append(.blank()) }
            if selectedPrivateTabID == id { selectedPrivateTabID = privateTabs.last!.id }
        } else {
            let spaceID = state.selectedSpaceID
            let priorTabs = state.selectedSpace?.tabs.map(\.id) ?? []
            persist { try $0.closeTab(id, in: spaceID) }
            guard priorTabs.contains(id), !(state.selectedSpace?.tabs.contains(where: { $0.id == id }) ?? false) else {
                return
            }
        }
        discardRuntimes(for: [id])
        pageRevision &+= 1
    }

    func navigate(to input: String) {
        guard let address = NativeBrowserAddress.resolve(input) else {
            statusMessage = "This address cannot be opened securely."
            return
        }
        statusMessage = nil
        webView(for: selectedTabID)?.load(URLRequest(url: address))
    }

    func goBack() { runtimes[selectedTabID]?.webView.goBack() }
    func goForward() { runtimes[selectedTabID]?.webView.goForward() }

    func reloadOrStop() {
        guard let page = runtimes[selectedTabID]?.webView else { return }
        if page.isLoading { page.stopLoading() } else { page.reload() }
        pageRevision &+= 1
    }

    func pageDidChange(_ tabID: UUID, page: WKWebView) {
        // A detached page can report a final redirect after a tab closes.
        // Never let it overwrite another tab's persisted state.
        guard runtimes[tabID]?.webView === page else { return }
        guard let url = page.url, NativeBrowserAddress.mayLoadAsMainDocument(url)
        else {
            pageRevision &+= 1
            return
        }
        let title = (page.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let address = url.absoluteString
        if let index = privateTabs.firstIndex(where: { $0.id == tabID }) {
            privateTabs[index].address = address
            privateTabs[index].title = title.isEmpty ? address : title
        } else if let old = state.spaces.flatMap(\.tabs).first(where: { $0.id == tabID }),
            old.address != address || old.title != (title.isEmpty ? address : title)
        {
            persist { try $0.recordNavigation(tabID, address: address, title: title) }
        }
        pageRevision &+= 1
    }

    func pageDidFail(_ error: Error, tabID: UUID, page: WKWebView) {
        guard runtimes[tabID]?.webView === page else { return }
        statusMessage = error.localizedDescription
        pageRevision &+= 1
    }

    func pageDidBlockNavigation(tabID: UUID, page: WKWebView, isPopup: Bool) {
        guard runtimes[tabID]?.webView === page else { return }
        statusMessage =
            isPopup
            ? "A popup with an insecure or unsupported address was blocked."
            : "An unencrypted or unsupported page was blocked. Use HTTPS."
        pageRevision &+= 1
    }

    /// New windows (for example, OAuth and 3-D Secure) must use the WebKit
    /// configuration of their opener. WebKit itself loads the new request.
    func openPopup(from openerID: UUID, requestURL: URL, configuration: WKWebViewConfiguration) -> WKWebView? {
        guard runtimes[openerID] != nil, NativeBrowserAddress.mayLoadAsMainDocument(requestURL) else { return nil }
        let tab: NativeBrowserTab
        if privateTabs.contains(where: { $0.id == openerID }) {
            tab = .blank()
            privateTabs.append(tab)
            selectedPrivateTabID = tab.id
            isPrivate = true
        } else {
            guard let source = state.spaces.first(where: { $0.tabs.contains(where: { $0.id == openerID }) }) else {
                return nil
            }
            var createdID: UUID?
            persist {
                createdID = try $0.newTab(in: source.id)
                try $0.selectSpace(source.id)
            }
            guard let createdID,
                let stored = state.spaces.first(where: { $0.id == source.id })?.tabs.first(where: { $0.id == createdID })
            else { return nil }
            tab = stored
            isPrivate = false
        }
        let runtime = NativeTabRuntime(
            tab: tab, configuration: configuration, owner: self,
            ruleList: contentBlockingEnabled ? contentRuleList : nil)
        runtimes[tab.id] = runtime
        pageRevision &+= 1
        return runtime.webView
    }

    func closePopup(_ tabID: UUID, page: WKWebView) {
        guard runtimes[tabID]?.webView === page else { return }
        if let index = privateTabs.firstIndex(where: { $0.id == tabID }) {
            privateTabs.remove(at: index)
            if privateTabs.isEmpty { privateTabs.append(.blank()) }
            if selectedPrivateTabID == tabID { selectedPrivateTabID = privateTabs.last!.id }
        } else if let spaceID = state.spaces.first(where: { $0.tabs.contains(where: { $0.id == tabID }) })?.id {
            persist { try $0.closeTab(tabID, in: spaceID) }
        }
        discardRuntimes(for: [tabID])
        pageRevision &+= 1
    }

    func beginDownload(_ download: WKDownload, tabID: UUID, page: WKWebView) {
        guard runtimes[tabID]?.webView === page else { return }
        downloadCenter.begin(download, isPrivate: privateTabs.contains(where: { $0.id == tabID }))
    }

    func downloadDidFinish(_ file: NativeCompletedDownload) {
        completedDownloads.insert(file, at: 0)
        statusMessage = "Download ready in Downloads."
    }

    func downloadDidFail(_ message: String) {
        statusMessage = message
    }

    func setContentBlockingEnabled(_ enabled: Bool) {
        guard let rule = contentRuleList, contentBlockingEnabled != enabled else { return }
        contentBlockingEnabled = enabled
        for runtime in runtimes.values {
            let controller = runtime.webView.configuration.userContentController
            if enabled { controller.add(rule) } else { controller.remove(rule) }
        }
        statusMessage = "Reload the page to apply content blocking changes."
    }

    func removeDownload(_ id: UUID) {
        guard let index = completedDownloads.firstIndex(where: { $0.id == id }) else { return }
        let file = completedDownloads.remove(at: index)
        try? FileManager.default.removeItem(at: file.fileURL.deletingLastPathComponent())
    }

    private func persist(_ change: (inout NativeBrowserState) throws -> Void) {
        do {
            var updated = state
            try change(&updated)
            try storage.save(updated)
            state = updated
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func discardRuntimes(for ids: Set<UUID>) {
        for id in ids {
            guard let runtime = runtimes.removeValue(forKey: id) else { continue }
            runtime.webView.navigationDelegate = nil
            runtime.webView.uiDelegate = nil
            runtime.webView.stopLoading()
        }
    }

    private func cleanupDeletedDataStores() {
        let identifiers = state.pendingDataStoreDeletions
        guard !identifiers.isEmpty else { return }
        Task { @MainActor [weak self] in
            // Release the old page hosts before WebKit attempts removal.
            await Task.yield()
            for id in identifiers {
                guard let self, self.state.pendingDataStoreDeletions.contains(id) else { continue }
                do {
                    try await WKWebsiteDataStore.remove(forIdentifier: id)
                    self.persist { $0.finishDataStoreDeletion(id) }
                } catch {
                    self.statusMessage = "Website data removal is pending: \(error.localizedDescription)"
                }
            }
        }
    }
}

@MainActor
final class NativeTabRuntime: NSObject, WKNavigationDelegate, WKUIDelegate {
    let id: UUID
    let webView: WKWebView
    private weak var owner: NativeBrowserSession?

    convenience init(
        tab: NativeBrowserTab, dataStore: WKWebsiteDataStore, owner: NativeBrowserSession,
        ruleList: WKContentRuleList?
    ) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        self.init(tab: tab, configuration: configuration, owner: owner, ruleList: ruleList, restore: true)
    }

    /// The provided configuration is required for a real WebKit opener/popup
    /// relationship. No custom process pool, cookies or authentication bridge.
    init(
        tab: NativeBrowserTab, configuration: WKWebViewConfiguration, owner: NativeBrowserSession,
        ruleList: WKContentRuleList?, restore: Bool = false
    ) {
        id = tab.id
        self.owner = owner
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        if let ruleList { configuration.userContentController.add(ruleList) }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        if restore, tab.address != "about:blank", let address = URL(string: tab.address),
            NativeBrowserAddress.mayLoadAsMainDocument(address)
        {
            webView.load(URLRequest(url: address))
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let target = action.targetFrame, !target.isMainFrame { return .allow }
        guard let url = action.request.url else { return .cancel }
        // WebKit may offer a user-initiated blob download generated by a page
        // that is already HTTPS. Do not load the blob as a normal document.
        if action.shouldPerformDownload && url.scheme?.lowercased() == "blob",
            action.sourceFrame.request.url?.scheme?.lowercased() == "https"
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
        guard response.isForMainFrame, !response.canShowMIMEType else { return .allow }
        return .download
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = action.request.url,
            NativeBrowserAddress.mayLoadAsMainDocument(url)
        else {
            owner?.pageDidBlockNavigation(tabID: id, page: webView, isPopup: true)
            return nil
        }
        return owner?.openPopup(from: id, requestURL: url, configuration: configuration)
    }

    func webViewDidClose(_ webView: WKWebView) {
        owner?.closePopup(id, page: webView)
    }

    /// JS dialogs are presented by the system, with the requesting frame's
    /// actual origin shown outside page content to prevent browser-UI spoofing.
    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let panel = siteDialog(message, frame: frame)
        panel.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        if !present(panel, from: webView) { completionHandler() }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let panel = siteDialog(message, frame: frame)
        panel.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        panel.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        if !present(panel, from: webView) { completionHandler(false) }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?, initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let panel = siteDialog(prompt, frame: frame)
        panel.addTextField { $0.text = defaultText }
        panel.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        panel.addAction(UIAlertAction(title: "OK", style: .default) { [weak panel] _ in
            completionHandler(panel?.textFields?.first?.text)
        })
        if !present(panel, from: webView) { completionHandler(nil) }
    }

    private func siteDialog(_ message: String, frame: WKFrameInfo) -> UIAlertController {
        let host = frame.request.url?.host ?? "Unknown website"
        return UIAlertController(
            title: "Message from \(host)",
            message: String(message.prefix(2_000)),
            preferredStyle: .alert
        )
    }

    private func present(_ dialog: UIAlertController, from webView: WKWebView) -> Bool {
        guard var presenter = webView.window?.rootViewController else { return false }
        while let presented = presenter.presentedViewController { presenter = presented }
        presenter.present(dialog, animated: true)
        return true
    }

    /// Let WebKit and iOS ask the person. Never grant site permissions
    /// persistently or bypass platform consent.
    func webView(
        _ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        .prompt
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        owner?.beginDownload(download, tabID: id, page: webView)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        owner?.beginDownload(download, tabID: id, page: webView)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        owner?.pageDidChange(id, page: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        owner?.pageDidChange(id, page: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        owner?.pageDidChange(id, page: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        owner?.pageDidFail(error, tabID: id, page: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        owner?.pageDidFail(error, tabID: id, page: webView)
    }
}
