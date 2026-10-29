import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserBraveContentRuleListTests: XCTestCase {
    func testBraveIOSBundleCompilesInAnIsolatedRuleListStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fennavio-brave-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try XCTUnwrap(WKContentRuleListStore(url: directory))
        let provider = BrowserContentRuleListProvider(
            core: CrestCore(), ruleListStore: store, modeOverride: .braveIOS)

        let lists = try await provider.balancedRuleLists()
        XCTAssertEqual(lists.count, 2)
        XCTAssertTrue(lists[0].identifier.hasPrefix("io.github.shipsen7.fennavio.brave."))
        let cached = try await provider.balancedRuleLists()
        XCTAssertTrue(lists[0] === cached[0])
    }

    func testRuleSourceDefaultsToPreviousFiltersAndRejectsUnknownValues() throws {
        let suite = "fennavio.brave-selection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(BrowserProtectionMode.selected(in: defaults), .fennavio)
        defaults.set(BrowserProtectionMode.braveIOS.name, forKey: BrowserProtectionMode.storageKey)
        XCTAssertEqual(BrowserProtectionMode.selected(in: defaults), .braveIOS)
        defaults.set("unknown", forKey: BrowserProtectionMode.storageKey)
        XCTAssertEqual(BrowserProtectionMode.selected(in: defaults), .fennavio)
    }

    func testBundledBraveResourceContainsOnlyExpectedNativeRuleActions() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "BraveIOSProtection", withExtension: "json"))
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        XCTAssertEqual(rules.count, 5_824)
        let actions = Set(rules.compactMap { ($0["action"] as? [String: Any])?["type"] as? String })
        XCTAssertEqual(actions, Set(["block", "ignore-previous-rules"]))
    }
}
