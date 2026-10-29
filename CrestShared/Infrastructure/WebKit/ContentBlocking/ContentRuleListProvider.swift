import CryptoKit
import Foundation
import WebKit

/// Compiles bundled WebKit filter data once. The core still owns each Space's
/// protection policy; the native adapter owns the engine's rule format.
@MainActor
final class BrowserContentRuleListProvider: BrowserContentRuleListProviding {
    // MARK: - Types

    private struct BundledRuleList: Decodable {
        let identifier: String
        let source: String
    }

    // MARK: - Static Variables

    /// Notebookcheck randomizes ad IDs after loading. Match only its dedicated
    /// ad wrappers, leaving editorial sidebars and related articles intact.
    private static let pageLayoutRules: ContentRuleList = {
        let source = #"""
            [{"trigger":{"url-filter":".*","if-domain":["*notebookcheck.com"]},
              "action":{"type":"css-display-none","selector":
                "aside.nbc-r-float-inline:has(> div.insert_inpage), .tx-nbc2fe-incontent-column:has(> aside.nbc-r-float-inline > div.insert_inpage), .tx-nbc2fe-incontent-column:has(> aside.first_incontent)"}}]
            """#
        let digest = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        return ContentRuleList(identifier: "io.github.shipsen7.fennavio.protection.\(digest)", source: source)
    }()

    // MARK: - Variables

    private let core: CrestCore
    private let bundle: Bundle
    private let updates: BrowserFilterListUpdates?
    private let ruleListStore: WKContentRuleListStore?
    private let compiler: any BrowserContentRuleListCompiling
    private var cachedRuleLists: [WKContentRuleList]?
    private var cachedBraveRuleLists: [WKContentRuleList]?
    private var cachedPageLayoutRuleList: WKContentRuleList?
    private let modeOverride: BrowserProtectionMode?

    private var currentMode: BrowserProtectionMode {
        #if os(iOS)
            modeOverride ?? BrowserProtectionMode.selected()
        #else
            modeOverride ?? .fennavio
        #endif
    }

    // MARK: - Initializers

    init(
        core: CrestCore,
        bundle: Bundle = .main,
        updates: BrowserFilterListUpdates? = nil,
        ruleListStore: WKContentRuleListStore? = .default(),
        compiler: any BrowserContentRuleListCompiling =
            BrowserContentRuleListCompilerAdapter(),
        modeOverride: BrowserProtectionMode? = nil
    ) {
        self.core = core
        self.bundle = bundle
        self.updates = updates
        self.ruleListStore = ruleListStore
        self.compiler = compiler
        self.modeOverride = modeOverride
    }

    // MARK: - Actions - Compiling

    /// The provider a launch uses: an isolated launch compiles into no store.
    static func forLaunch(
        core: CrestCore,
        launchEnvironment: BrowserLaunchEnvironment = .current
    ) -> BrowserContentRuleListProvider {
        guard !launchEnvironment.requiresIsolation else {
            return BrowserContentRuleListProvider(core: core, ruleListStore: nil)
        }
        let updates = BrowserFilterListUpdates.shared
        updates.activate()
        return BrowserContentRuleListProvider(core: core, updates: updates)
    }

    func balancedRuleLists() async throws -> [WKContentRuleList] {
        guard let ruleListStore else { return [] }
        if currentMode == .braveIOS {
            // Genuine Brave iOS WebKit baseline, not the complete Rust engine.
            if let cachedBraveRuleLists { return cachedBraveRuleLists }
            do {
                let rule = try bundledBraveRuleList()
                let lists = try await compiler.compile(
                    identifiers: [rule.identifier], sources: [rule.source], store: ruleListStore)
                let complete = try await applyingPageLayoutRules(to: lists, store: ruleListStore)
                cachedBraveRuleLists = complete
                return complete
            } catch {
                // Never turn protection off silently because Brave failed.
                return try await previousRuleLists(store: ruleListStore)
            }
        }
        return try await previousRuleLists(store: ruleListStore)
    }

    private func previousRuleLists(store ruleListStore: WKContentRuleListStore) async throws
        -> [WKContentRuleList]
    {
        if let lists = await updates?.cachedLists(store: ruleListStore) {
            return try await applyingPageLayoutRules(to: lists, store: ruleListStore)
        }
        if updates?.hasCustomSelection == true { throw BrowserContentBlockingError.compilationFailed }
        if let cachedRuleLists { return cachedRuleLists }
        let rules: [ContentRuleList]
        if let bundled = try bundledRuleLists() {
            rules = bundled
        } else {
            guard let baseline = try? core.query(BalancedProtectionRules()) else { return [] }
            rules = [baseline]
        }

        let ruleLists = try await compiler.compile(
            identifiers: rules.map(\.identifier),
            sources: rules.map(\.source),
            store: ruleListStore
        )
        let complete = try await applyingPageLayoutRules(to: ruleLists, store: ruleListStore)
        cachedRuleLists = complete
        return complete
    }

    private func applyingPageLayoutRules(to lists: [WKContentRuleList], store: WKContentRuleListStore) async throws
        -> [WKContentRuleList]
    {
        // Turning every subscription off must still install no rules.
        guard !lists.isEmpty else { return [] }
        if let cachedPageLayoutRuleList { return lists + [cachedPageLayoutRuleList] }
        let rules = Self.pageLayoutRules
        let compiled = try await compiler.compile(
            identifiers: [rules.identifier], sources: [rules.source], store: store)
        cachedPageLayoutRuleList = compiled.first
        return lists + compiled
    }

    /// The unmodified Brave iOS bundled WebKit rule set, available offline.
    private func bundledBraveRuleList() throws -> ContentRuleList {
        guard let url = bundle.url(forResource: "BraveIOSProtection", withExtension: "json") else {
            throw BrowserContentBlockingError.ruleListUnavailable
        }
        let data = try Data(contentsOf: url)
        guard let source = String(data: data, encoding: .utf8),
            let rules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            !rules.isEmpty
        else {
            throw BrowserContentBlockingError.compilationFailed
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ContentRuleList(identifier: "io.github.shipsen7.fennavio.brave.\(digest)", source: source)
    }

    private func bundledRuleLists() throws -> [ContentRuleList]? {
        guard let url = bundle.url(forResource: "FennavioProtection", withExtension: "json") else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([BundledRuleList].self, from: data).map { rules in
            let digest = SHA256.hash(data: Data(rules.source.utf8)).map { String(format: "%02x", $0) }.joined()
            guard rules.identifier == "io.github.shipsen7.fennavio.protection.\(digest)" else {
                throw BrowserContentBlockingError.compilationFailed
            }
            return ContentRuleList(identifier: rules.identifier, source: rules.source)
        }
    }
}
