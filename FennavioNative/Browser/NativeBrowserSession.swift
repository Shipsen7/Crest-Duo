import Foundation
import Observation
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

    @ObservationIgnored private let storage: NativeBrowserStorage
    @ObservationIgnored private var privateDataStore = WKWebsiteDataStore.nonPersistent()
    @ObservationIgnored private var runtimes: [UUID: NativeTabRuntime] = [:]

    init(storage: NativeBrowserStorage? = nil) throws {
        let storage = try storage ?? NativeBrowserStorage()
        self.storage = storage
        state = try storage.load()
        let first = NativeBrowserTab.blank()
        privateTabs = [first]
        selectedPrivateTabID = first.id
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

    func webView(for tabID: UUID) -> WKWebView? {
        if let existing = runtimes[tabID] { return existing.webView }
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return nil }
        let websiteDataStore =
            isPrivate
            ? privateDataStore : WKWebsiteDataStore(forIdentifier: state.selectedSpaceID)
        let runtime = NativeTabRuntime(tab: tab, dataStore: websiteDataStore, owner: self)
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
        guard let address = NativeBrowserAddress.resolve(input) else { return }
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
        guard let url = page.url,
            url.absoluteString == "about:blank" || (["https", "http"].contains(url.scheme ?? "") && url.host != nil)
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

    func pageDidFail(_ error: Error) {
        statusMessage = error.localizedDescription
        pageRevision &+= 1
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
            runtime.webView.stopLoading()
            runtime.webView.navigationDelegate = nil
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
final class NativeTabRuntime: NSObject, WKNavigationDelegate {
    let id: UUID
    let webView: WKWebView
    private weak var owner: NativeBrowserSession?

    init(tab: NativeBrowserTab, dataStore: WKWebsiteDataStore, owner: NativeBrowserSession) {
        id = tab.id
        self.owner = owner
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        if tab.address != "about:blank", let address = URL(string: tab.address) {
            webView.load(URLRequest(url: address))
        }
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
        owner?.pageDidFail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        owner?.pageDidFail(error)
    }
}
