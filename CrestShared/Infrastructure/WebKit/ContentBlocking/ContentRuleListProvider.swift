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

    // MARK: - Variables

    private let core: CrestCore
    private let bundle: Bundle
    private let updates: BrowserFilterListUpdates?
    private let ruleListStore: WKContentRuleListStore?
    private let compiler: any BrowserContentRuleListCompiling
    private var cachedRuleLists: [WKContentRuleList]?

    // MARK: - Initializers

    init(
        core: CrestCore,
        bundle: Bundle = .main,
        updates: BrowserFilterListUpdates? = nil,
        ruleListStore: WKContentRuleListStore? = .default(),
        compiler: any BrowserContentRuleListCompiling =
            BrowserContentRuleListCompilerAdapter()
    ) {
        self.core = core
        self.bundle = bundle
        self.updates = updates
        self.ruleListStore = ruleListStore
        self.compiler = compiler
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
        if let lists = await updates?.cachedLists(store: ruleListStore) { return lists }
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
        cachedRuleLists = ruleLists
        return ruleLists
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
