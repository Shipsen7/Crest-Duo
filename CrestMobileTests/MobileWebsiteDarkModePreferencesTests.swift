import Foundation
import XCTest

@testable import CrestMobile

@MainActor
final class MobileWebsiteDarkModePreferencesTests: XCTestCase {
    // MARK: - Actions - Persistence and isolation

    func testAppearancePersistsOnlyForTheExactOriginAndProfile() throws {
        let suite = "fennavio-dark-mode-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = UUID()
        let otherProfile = UUID()
        let origin = try site("https://example.test/one")
        let preferences = MobileWebsiteDarkModePreferences(defaults: defaults)
        XCTAssertFalse(preferences.isEnabled(for: origin, in: profile))
        preferences.setEnabled(true, for: origin, in: profile)

        let restored = MobileWebsiteDarkModePreferences(defaults: defaults)
        XCTAssertTrue(restored.isEnabled(for: try site("https://example.test:443/two"), in: profile))
        XCTAssertFalse(restored.isEnabled(for: origin, in: otherProfile))
        for url in ["http://example.test", "https://example.test:444", "https://www.example.test"] {
            XCTAssertFalse(restored.isEnabled(for: try site(url), in: profile), url)
        }
        restored.setEnabled(false, for: origin, in: profile)
        XCTAssertTrue(MobileWebsiteDarkModePreferences(defaults: defaults).enabledOrigins(in: profile).isEmpty)
    }

    func testPrivateChoicesNeverReadOrWriteNormalPreferences() throws {
        let suite = "fennavio-dark-mode-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = UUID()
        let origin = try site("https://example.test")
        let ordinary = MobileWebsiteDarkModePreferences(defaults: defaults)
        ordinary.setEnabled(true, for: origin, in: profile)
        let before = defaults.dictionaryRepresentation()
        let privatePreferences = MobileWebsiteDarkModePreferences()
        XCTAssertFalse(privatePreferences.isEnabled(for: origin, in: profile))
        privatePreferences.setEnabled(true, for: try site("https://private.test"), in: profile)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        XCTAssertFalse(MobileWebsiteDarkModePreferences().isEnabled(for: try site("https://private.test"), in: profile))
    }

    func testRemovingOneProfilePreservesTheOthers() throws {
        let preferences = MobileWebsiteDarkModePreferences()
        let first = UUID()
        let second = UUID()
        let origin = try site("https://example.test")
        preferences.setEnabled(true, for: origin, in: first)
        preferences.setEnabled(true, for: origin, in: second)
        preferences.removeProfile(first)
        XCTAssertTrue(preferences.enabledOrigins(in: first).isEmpty)
        XCTAssertTrue(preferences.isEnabled(for: origin, in: second))
    }

    // MARK: - Actions - Fixtures

    private func site(_ url: String) throws -> SiteOrigin {
        try XCTUnwrap(URL(string: url).flatMap(SiteOrigin.init(url:)))
    }
}
