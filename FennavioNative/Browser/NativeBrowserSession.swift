import Foundation
import Observation
import WebKit

/// Owns regular/private browsing state and native page lifetimes. No external
/// engine, credential bridge, shared container or synchronization transport.
@MainActor
@Observable
final class NativeBrowserSession {
    private(set) var state: NativeBrowserState
    private(set) var library: NativePageLibrary
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
    @ObservationIgnored private let downloadCenter: NativeDownloadCenter
    @ObservationIgnored private let contentRuleList: WKContentRuleList?
    @ObservationIgnored private var isForeground = true
    @ObservationIgnored private var isCleaningLegacyStores = false

    init(storage: NativeBrowserStorage? = nil, contentRuleList: WKContentRuleList? = nil, downloadDirectory: URL? = nil)
        throws
    {
        let storage = try storage ?? NativeBrowserStorage()
        self.storage = storage
        self.contentRuleList = contentRuleList
        contentBlockingEnabled = contentRuleList != nil
        state = try storage.load()
        library = try storage.loadLibrary()
        if let downloadDirectory {
            downloadCenter = try NativeDownloadCenter(directory: downloadDirectory)
        } else {
            downloadCenter = try NativeDownloadCenter()
        }
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
    var visibleDownloads: [NativeCompletedDownload] { completedDownloads.filter { $0.isPrivate == isPrivate } }
    var currentHost: String? {
        _ = pageRevision
        return runtimes[selectedTabID]?.secureHost
    }

    var isCurrentPageBookmarked: Bool {
        _ = pageRevision
        guard !isPrivate, let url = runtimes[selectedTabID]?.webView.url else { return false }
        return library.isBookmarked(url)
    }

    func setForeground(_ active: Bool) {
        isForeground = active
        if !active { dismissSiteDialogs() }
    }

    func allowsInteraction(from tabID: UUID) -> Bool {
        isForeground && selectedTabID == tabID && runtimes[tabID] != nil
    }

    func toggleCurrentBookmark() {
        guard !isPrivate, let runtime = runtimes[selectedTabID], runtime.canRecordDocument,
            let url = runtime.webView.url, NativeBrowserAddress.isHTTPS(url)
        else { return }
        updateLibrary { $0.toggleBookmark(url, title: runtime.webView.title ?? url.absoluteString) }
    }

    func removeBookmark(_ page: NativeSavedPage) {
        guard let url = URL(string: page.address), library.isBookmarked(url) else { return }
        updateLibrary { $0.toggleBookmark(url, title: page.title) }
    }

    func clearHistory() { updateLibrary { $0.clearHistory() } }
    func openSavedPage(_ page: NativeSavedPage) { navigate(to: page.address) }

    func webView(for tabID: UUID) -> WKWebView? {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return nil }
        if let existing = runtimes[tabID] { return existing.webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = isPrivate ? privateDataStore : .default()
        let runtime = NativeTabRuntime(
            tabID: tab.id, configuration: configuration, owner: self,
            ruleList: contentBlockingEnabled ? contentRuleList : nil, isPopup: false)
        runtimes[tabID] = runtime
        // Install ownership before the first navigation can call its delegate.
        if tab.address != "about:blank", let url = URL(string: tab.address), NativeBrowserAddress.isHTTPS(url) {
            runtime.webView.load(URLRequest(url: url))
        }
        return runtime.webView
    }

    func switchToSpace(_ id: UUID) {
        guard persist({ try $0.selectSpace(id) }) else { return }
        dismissSiteDialogs()
        isPrivate = false
        statusMessage = nil
    }

    func switchToPrivate() {
        dismissSiteDialogs()
        isPrivate = true
        statusMessage = nil
    }

    func endPrivateSession() {
        dismissSiteDialogs()
        discardRuntimes(for: Set(privateTabs.map(\.id)))
        downloadCenter.cancelPrivate()
        var failedCleanup = false
        for file in completedDownloads where file.isPrivate {
            do { try FileManager.default.removeItem(at: file.fileURL.deletingLastPathComponent()) } catch {
                failedCleanup = true
            }
        }
        completedDownloads.removeAll { $0.isPrivate }
        privateDataStore = .nonPersistent()
        let first = NativeBrowserTab.blank()
        privateTabs = [first]
        selectedPrivateTabID = first.id
        isPrivate = false
        statusMessage =
            failedCleanup ? "Temporary private-file cleanup failed. Close and reopen the app to retry." : nil
        pageRevision &+= 1
    }

    func createSpace(name: String) {
        guard persist({ _ = $0.createSpace(name: name) }) else { return }
        dismissSiteDialogs()
        isPrivate = false
    }

    func renameSpace(_ id: UUID, to name: String) { persist { try $0.renameSpace(id, to: name) } }
    func reorderSpaces(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        persist { try $0.reorderSpaces(fromOffsets: offsets, toOffset: destination) }
    }
    func reorderTabs(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard !isPrivate else { return }
        let spaceID = state.selectedSpaceID
        persist { try $0.reorderTabs(in: spaceID, fromOffsets: offsets, toOffset: destination) }
    }

    func moveTab(_ id: UUID, to destinationID: UUID) {
        guard !isPrivate else { return }
        let sourceID = state.selectedSpaceID
        guard sourceID != destinationID,
            persist({ try $0.moveTab(id, from: sourceID, to: destinationID) })
        else { return }
        dismissSiteDialogs()
        pageRevision &+= 1
    }

    func deleteSpace(_ id: UUID) {
        guard let space = state.spaces.first(where: { $0.id == id }), persist({ try $0.deleteSpace(id) }) else {
            return
        }
        discardRuntimes(for: Set(space.tabs.map(\.id)))
        isPrivate = false
        pageRevision &+= 1
    }

    func newTab() {
        dismissSiteDialogs()
        if isPrivate {
            guard privateTabs.count < 1_000 else {
                statusMessage = "Close unused private tabs first."
                return
            }
            let tab = NativeBrowserTab.blank()
            privateTabs.append(tab)
            selectedPrivateTabID = tab.id
            statusMessage = nil
        } else {
            let spaceID = state.selectedSpaceID
            persist { _ = try $0.newTab(in: spaceID) }
        }
    }

    func selectTab(_ id: UUID) {
        dismissSiteDialogs()
        if isPrivate {
            guard privateTabs.contains(where: { $0.id == id }) else { return }
            selectedPrivateTabID = id
            statusMessage = nil
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
            if selectedPrivateTabID == id { selectedPrivateTabID = privateTabs[0].id }
        } else {
            let spaceID = state.selectedSpaceID
            guard persist({ try $0.closeTab(id, in: spaceID) }) else { return }
        }
        discardRuntimes(for: [id])
        pageRevision &+= 1
    }

    func navigate(to input: String) {
        guard let url = NativeBrowserAddress.resolve(input) else {
            statusMessage = "This address cannot be opened securely."
            return
        }
        dismissSiteDialogs()
        statusMessage = nil
        webView(for: selectedTabID)?.load(URLRequest(url: url))
    }

    func goBack() {
        dismissSiteDialogs()
        runtimes[selectedTabID]?.webView.goBack()
    }
    func goForward() {
        dismissSiteDialogs()
        runtimes[selectedTabID]?.webView.goForward()
    }
    func reloadOrStop() {
        guard let page = runtimes[selectedTabID]?.webView else { return }
        dismissSiteDialogs()
        statusMessage = nil
        if page.isLoading { page.stopLoading() } else { page.reload() }
        pageRevision &+= 1
    }

    /// Provisional requests are not visits. Only WebKit-committed documents
    /// may update persisted addresses; queued callbacks from closed tabs lose ownership.
    func pageDidChange(_ tabID: UUID, page: WKWebView) {
        guard let runtime = runtimes[tabID], runtime.webView === page else { return }
        pageRevision &+= 1
        guard runtime.canRecordDocument, let url = page.url, NativeBrowserAddress.mayLoadAsMainDocument(url) else {
            return
        }
        let rawTitle = (page.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let address = url.absoluteString
        let title = String((rawTitle.isEmpty ? address : rawTitle).prefix(1_024))
        if let index = privateTabs.firstIndex(where: { $0.id == tabID }) {
            privateTabs[index].address = address
            privateTabs[index].title = title
        } else {
            if let old = state.spaces.flatMap(\.tabs).first(where: { $0.id == tabID }),
                old.address != address || old.title != title
            {
                persist { try $0.recordNavigation(tabID, address: address, title: title) }
            }
            if NativeBrowserAddress.isHTTPS(url) { updateLibrary { $0.recordVisit(url, title: title) } }
        }
    }

    func pageDidFail(_ message: String, tabID: UUID, page: WKWebView) {
        guard runtimes[tabID]?.webView === page else { return }
        // A background/private tab must not disclose its errors in another tab.
        if allowsInteraction(from: tabID) { statusMessage = message }
        pageRevision &+= 1
    }

    func pageDidBlockNavigation(tabID: UUID, page: WKWebView, isPopup: Bool) {
        pageDidFail(
            isPopup
                ? "An unsupported popup was blocked." : "An unencrypted or unsupported page was blocked. Use HTTPS.",
            tabID: tabID, page: page)
    }

    func openPopup(from openerID: UUID, requestURL: URL, configuration: WKWebViewConfiguration) -> WKWebView? {
        guard allowsInteraction(from: openerID), NativeBrowserAddress.mayLoadAsMainDocument(requestURL) else {
            return nil
        }
        let tab: NativeBrowserTab
        if privateTabs.contains(where: { $0.id == openerID }) {
            guard privateTabs.count < 1_000 else { return nil }
            tab = .blank()
            privateTabs.append(tab)
            selectedPrivateTabID = tab.id
        } else {
            guard let source = state.spaces.first(where: { $0.tabs.contains(where: { $0.id == openerID }) }) else {
                return nil
            }
            var createdID: UUID?
            guard
                persist({
                    createdID = try $0.newTab(in: source.id)
                    try $0.selectSpace(source.id)
                }),
                let createdID,
                let stored = state.spaces.first(where: { $0.id == source.id })?.tabs.first(where: { $0.id == createdID }
                )
            else { return nil }
            tab = stored
        }
        dismissSiteDialogs()
        let runtime = NativeTabRuntime(
            tabID: tab.id, configuration: configuration, owner: self,
            ruleList: contentBlockingEnabled ? contentRuleList : nil, isPopup: true)
        runtimes[tab.id] = runtime
        pageRevision &+= 1
        return runtime.webView
    }

    func closePopup(_ tabID: UUID, page: WKWebView) {
        guard let runtime = runtimes[tabID], runtime.webView === page, runtime.isPopup else { return }
        if let index = privateTabs.firstIndex(where: { $0.id == tabID }) {
            privateTabs.remove(at: index)
            if privateTabs.isEmpty { privateTabs.append(.blank()) }
            if selectedPrivateTabID == tabID { selectedPrivateTabID = privateTabs[0].id }
        } else {
            guard let spaceID = state.spaces.first(where: { $0.tabs.contains(where: { $0.id == tabID }) })?.id,
                persist({ try $0.closeTab(tabID, in: spaceID) })
            else { return }
        }
        discardRuntimes(for: [tabID])
        pageRevision &+= 1
    }

    func beginDownload(_ download: WKDownload, tabID: UUID, page: WKWebView) {
        guard runtimes[tabID]?.webView === page, completedDownloads.count + downloadCenter.activeCount < 20 else {
            download.cancel(nil)
            if allowsInteraction(from: tabID) {
                statusMessage = "Download unavailable. Remove older temporary downloads first."
            }
            return
        }
        downloadCenter.begin(download, isPrivate: privateTabs.contains(where: { $0.id == tabID }))
    }

    func downloadDidFinish(_ file: NativeCompletedDownload) {
        completedDownloads.insert(file, at: 0)
        if file.isPrivate == isPrivate { statusMessage = "Download ready in Downloads." }
    }
    func downloadDidFail(_ message: String, isPrivate privateDownload: Bool) {
        if privateDownload == isPrivate { statusMessage = message }
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
        do {
            try FileManager.default.removeItem(at: completedDownloads[index].fileURL.deletingLastPathComponent())
            completedDownloads.remove(at: index)
        } catch { statusMessage = "The temporary file could not be removed. Try again after unlocking the device." }
    }

    private func updateLibrary(_ change: (inout NativePageLibrary) -> Void) {
        var updated = library
        change(&updated)
        guard updated != library else { return }
        do {
            try storage.saveLibrary(updated)
            library = updated
        } catch { statusMessage = "Could not save browsing history or bookmarks. Existing data was kept." }
    }

    @discardableResult
    private func persist(_ change: (inout NativeBrowserState) throws -> Void) -> Bool {
        do {
            var updated = state
            try change(&updated)
            try storage.save(updated)
            state = updated
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func dismissSiteDialogs() { for runtime in runtimes.values { runtime.dismissSiteDialog() } }
    private func discardRuntimes(for ids: Set<UUID>) {
        for id in ids { runtimes.removeValue(forKey: id)?.detach() }
    }

    private func cleanupDeletedDataStores() {
        guard !isCleaningLegacyStores, !state.pendingDataStoreDeletions.isEmpty else { return }
        isCleaningLegacyStores = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isCleaningLegacyStores = false }
            for id in self.state.pendingDataStoreDeletions {
                do {
                    try await WKWebsiteDataStore.remove(forIdentifier: id)
                    self.persist { $0.finishDataStoreDeletion(id) }
                } catch { self.statusMessage = "Earlier native-preview website-data cleanup is pending." }
            }
        }
    }
}
