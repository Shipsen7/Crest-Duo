import XCTest

@testable import Crest

/// A browser layout belongs to a device context, never a browsing Space.
@MainActor
final class BrowserChromeLayoutPreferenceStoreTests: XCTestCase {
    func testIndependentProfilesPersistAndResetWithoutAffectingOtherLayouts() throws {
        let suite = "fennavio.layout-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = BrowserChromeLayoutPreferenceStore(defaults: defaults)
        XCTAssertEqual(store.options(for: .duoFolded), .compactDefault)
        XCTAssertEqual(store.options(for: .duoUnfolded), .expandedDefault)
        XCTAssertEqual(store.options(for: .mac), .desktopDefault)

        var folded = store.options(for: .duoFolded)
        folded.addressPosition = .top
        folded.visualStyle = .calm
        store.set(folded, for: .duoFolded)

        var mac = store.options(for: .mac)
        mac.tabStripVisibility = .onDemand
        store.set(mac, for: .mac)

        let reloaded = BrowserChromeLayoutPreferenceStore(defaults: defaults)
        XCTAssertEqual(reloaded.options(for: .duoFolded), folded)
        XCTAssertEqual(reloaded.options(for: .duoUnfolded), .expandedDefault)
        XCTAssertEqual(reloaded.options(for: .iPad), .tabletDefault)
        XCTAssertEqual(reloaded.options(for: .mac), mac)

        reloaded.restoreDefaults(for: .duoFolded)
        let afterReset = BrowserChromeLayoutPreferenceStore(defaults: defaults)
        XCTAssertEqual(afterReset.options(for: .duoFolded), .compactDefault)
        XCTAssertEqual(afterReset.options(for: .mac), mac)
    }

    func testMobileContextResolutionDoesNotInferAnUnfoldedDuoFromWidth() {
        XCTAssertEqual(BrowserChromeDeviceProfile.mobile(isTablet: false, isInnerFoldableDisplay: false), .duoFolded)
        XCTAssertEqual(BrowserChromeDeviceProfile.mobile(isTablet: false, isInnerFoldableDisplay: true), .duoUnfolded)
        XCTAssertEqual(BrowserChromeDeviceProfile.mobile(isTablet: true, isInnerFoldableDisplay: false), .iPad)
        XCTAssertEqual(BrowserChromeDeviceProfile.mobile(isTablet: true, isInnerFoldableDisplay: true), .iPad)
    }

    func testCorruptProfileCannotEraseOtherSavedProfiles() throws {
        let suite = "fennavio.layout-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = BrowserChromeLayoutPreferenceStore(defaults: defaults)
        var tablet = store.options(for: .iPad)
        tablet.navigationPosition = .top
        store.set(tablet, for: .iPad)
        defaults.set(Data("not-json".utf8), forKey: BrowserChromeLayoutPreferenceStore.storageKeyPrefix + "duo-folded")

        let reloaded = BrowserChromeLayoutPreferenceStore(defaults: defaults)
        XCTAssertEqual(reloaded.options(for: .duoFolded), .compactDefault)
        XCTAssertEqual(reloaded.options(for: .iPad), tablet)
    }
}
