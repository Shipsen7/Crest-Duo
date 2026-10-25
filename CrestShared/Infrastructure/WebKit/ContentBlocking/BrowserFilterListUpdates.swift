import CryptoKit
import Foundation
import Observation
import WebKit

/// The public protection subscription, shared by WebKit windows. It contains
/// no Space records or website data; each page still applies its core policy.
@MainActor
@Observable
final class BrowserFilterListUpdates {
    // MARK: - Types

    private struct Configuration: Decodable {
        let sources: [URL]
        let subscriptions: [Subscription]
    }

    struct Subscription: Decodable, Identifiable {
        let id: String
        let title: String
        let sources: [URL]
    }

    // MARK: - Static Variables

    static let shared = BrowserFilterListUpdates()

    // MARK: - Variables

    var hasCustomSelection: Bool { selection?.isEmpty == false }
    private(set) var subscriptions: [Subscription] = []
    @ObservationIgnored private var configuration: Configuration?
    @ObservationIgnored private var supportDirectory: URL?
    @ObservationIgnored private var bundledSources: [String: String] = [:]
    @ObservationIgnored private var selection: [String]?
    private(set) var isAvailable = false
    private(set) var isUpdating = false
    private(set) var updatedAt: Date?
    private(set) var ruleCount = 0
    private(set) var generation = 0
    private(set) var failed = false
    @ObservationIgnored private var repository: BrowserFilterListRepository?
    @ObservationIgnored private var compiledLists: [WKContentRuleList]?
    @ObservationIgnored private var inputDigest: String?
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var lastCheck: Date?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    // MARK: - Actions - Preparation

    /// Only the ordinary launch composition activates network access. Isolated
    /// sessions and previews never call this entry point.
    func activate(bundle: Bundle = .main) {
        guard !isAvailable,
            let url = bundle.url(forResource: "FennavioFilters", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let configuration = try? JSONDecoder().decode(Configuration.self, from: data),
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        self.configuration = configuration
        subscriptions = configuration.subscriptions
        supportDirectory = support.appendingPathComponent("Fennavio/FilterLists", isDirectory: true)
        if let sourceURL = bundle.url(forResource: "FennavioFilterSources", withExtension: "json"),
            let sourceData = try? Data(contentsOf: sourceURL)
        {
            bundledSources = (try? JSONDecoder().decode([String: String].self, from: sourceData)) ?? [:]
        }
        configureSelection()
        isAvailable = true
    }

    func cachedLists(store: WKContentRuleListStore) async -> [WKContentRuleList]? {
        if let compiledLists { return compiledLists }
        guard let repository else { return nil }
        let selected = selection
        var snapshot = try? await repository.load()
        if snapshot == nil, selection?.isEmpty == false || selectedURLs.isEmpty {
            snapshot = try? await repository.candidate(previousDigest: nil, force: false, downloads: false)
        }
        guard let snapshot, let lists = try? await compile(snapshot, store: store), selected == selection else {
            return nil
        }
        if let compiledLists { return compiledLists }
        adopt(snapshot, lists: lists)
        generation &+= 1
        lastCheck = await repository.lastCheck()
        return lists
    }

    // MARK: - Actions - Updating

    func refresh(force: Bool = false) async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        configureSelection()
        let selected = selection
        guard let repository, let store = WKContentRuleListStore.default() else { return }
        let now = Date()
        if !force {
            if let lastAttempt, now.timeIntervalSince(lastAttempt) < 3600 { return }
        }
        lastAttempt = now
        isUpdating = true
        let task = Task {
            defer { isUpdating = false }
            do {
                _ = await cachedLists(store: store)
                if let candidate = try await repository.candidate(previousDigest: inputDigest, force: force) {
                    let lists =
                        candidate.inputDigest == inputDigest
                        ? compiledLists ?? []
                        : try await compile(candidate, store: store)
                    guard selected == selection else { return }
                    // Persist only after every list compiled. A failed fetch,
                    // conversion, compile or disk write preserves the old set.
                    try await repository.commit(candidate)
                    adopt(candidate, lists: lists)
                    generation &+= 1
                    let retained = Set(candidate.lists.map(\.identifier))
                    for identifier in await BrowserContentRuleListCompiler.availableIdentifiers(store: store)
                    where identifier.hasPrefix("io.github.shipsen7.fennavio.protection.")
                        && !retained.contains(identifier)
                    {
                        await BrowserContentRuleListCompiler.remove(identifier: identifier, store: store)
                    }
                }
                try? await repository.recordCheck()
                failed = false
                lastCheck = Date()
            } catch {
                failed = true
            }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
        if selection != BrowserAppPreferenceStore.shared.disabledFilterLists.sorted() {
            await refresh()
        }
    }

    func refreshWhileActive() async {
        guard isAvailable else { return }
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: .seconds(3600)) } catch { return }
        }
    }

    private var selectedURLs: [URL] {
        subscriptions.filter { !(selection ?? []).contains($0.id) }.flatMap(\.sources)
    }

    private func configureSelection() {
        let disabled = BrowserAppPreferenceStore.shared.disabledFilterLists.sorted()
        guard selection != disabled, let supportDirectory, configuration != nil else { return }
        selection = disabled
        let key = SHA256.hash(data: Data(selectedURLs.map(\.absoluteString).joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
        repository = BrowserFilterListRepository(
            directory: supportDirectory.appendingPathComponent(key, isDirectory: true),
            sourceURLs: selectedURLs, minimumRuleCount: disabled.isEmpty ? 20_000 : 1, bundledSources: bundledSources)
        compiledLists = nil
        inputDigest = nil
        lastAttempt = nil
        lastCheck = nil
        updatedAt = nil
        ruleCount = 0
    }

    private func compile(_ snapshot: BrowserFilterRuleSet, store: WKContentRuleListStore) async throws
        -> [WKContentRuleList]
    {
        try await BrowserContentRuleListCompilerAdapter().compile(
            identifiers: snapshot.lists.map(\.identifier), sources: snapshot.lists.map(\.source), store: store
        )
    }

    private func adopt(_ snapshot: BrowserFilterRuleSet, lists: [WKContentRuleList]) {
        compiledLists = lists
        inputDigest = snapshot.inputDigest
        updatedAt = snapshot.updatedAt
        ruleCount = snapshot.ruleCount
    }
}
