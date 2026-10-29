import Foundation
import XCTest

@testable import FennavioNativePreview

final class NativeBrowserStateTests: XCTestCase {
    func testSpacesKeepIndependentTabOwnershipAndSelection() throws {
        var state = NativeBrowserState()
        let originalID = state.selectedSpaceID
        let originalTabID = try XCTUnwrap(state.selectedSpace?.selectedTabID)
        let secondID = state.createSpace(name: "Reading")
        let secondTabID = try state.newTab(in: secondID)
        try state.selectSpace(originalID)

        XCTAssertEqual(state.selectedSpace?.selectedTabID, originalTabID)
        XCTAssertEqual(state.spaces.first(where: { $0.id == secondID })?.selectedTabID, secondTabID)
        XCTAssertNotEqual(originalTabID, secondTabID)
        try state.validate()
    }

    func testSpaceDeletionRetainsWebsiteDataRemovalRequestUntilConfirmed() throws {
        var state = NativeBrowserState()
        let originalID = state.selectedSpaceID
        _ = state.createSpace(name: "Work")
        try state.deleteSpace(originalID)

        XCTAssertTrue(state.pendingDataStoreDeletions.contains(originalID))
        XCTAssertFalse(state.spaces.contains(where: { $0.id == originalID }))
        state.finishDataStoreDeletion(originalID)
        XCTAssertFalse(state.pendingDataStoreDeletions.contains(originalID))
        try state.validate()
    }

    func testCannotDeleteLastSpace() {
        var state = NativeBrowserState()
        XCTAssertThrowsError(try state.deleteSpace(state.selectedSpaceID))
        XCTAssertEqual(state.spaces.count, 1)
    }

    func testClosingLastTabReplacesItWithNewBlankTab() throws {
        var state = NativeBrowserState()
        let selectedSpace = state.selectedSpaceID
        let oldID = try XCTUnwrap(state.selectedSpace?.selectedTabID)
        try state.closeTab(oldID, in: selectedSpace)

        XCTAssertEqual(state.selectedSpace?.tabs.count, 1)
        XCTAssertEqual(state.selectedSpace?.selectedTab?.address, "about:blank")
        XCTAssertNotEqual(state.selectedSpace?.selectedTabID, oldID)
        try state.validate()
    }

    func testStatePersistsAndCorruptionDoesNotGetOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fileURL = folder.appendingPathComponent("state.json")
        let storage = NativeBrowserStorage(fileURL: fileURL)
        var state = NativeBrowserState()
        _ = state.createSpace(name: "Books")
        try storage.save(state)
        XCTAssertEqual(try storage.load(), state)

        try "not-json".write(to: fileURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try storage.load())
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "not-json")
    }

    func testUnsupportedStoredSchemaCannotBeLoaded() throws {
        var state = NativeBrowserState()
        state.schemaVersion = 999
        XCTAssertThrowsError(try state.validate())
    }

    func testReorderingSpacesAndTabsRetainsStableOwnership() throws {
        var state = NativeBrowserState()
        let first = state.selectedSpaceID
        let firstTab = try XCTUnwrap(state.selectedSpace?.selectedTabID)
        let secondTab = try state.newTab(in: first)
        let second = state.createSpace(name: "Reading")
        try state.reorderSpaces(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(state.spaces.map(\.id), [second, first])
        try state.reorderTabs(in: first, fromOffsets: IndexSet(integer: 0), toOffset: 2)
        XCTAssertEqual(state.spaces.last?.tabs.map(\.id), [secondTab, firstTab])
        try state.validate()
    }

    func testMovingTabBetweenGroupsPreservesID() throws {
        var state = NativeBrowserState()
        let source = state.selectedSpaceID
        let movedTab = try XCTUnwrap(state.selectedSpace?.selectedTabID)
        try state.recordNavigation(movedTab, address: "https://example.com", title: "Example")
        let destination = state.createSpace(name: "Reading")
        try state.moveTab(movedTab, from: source, to: destination)
        let moved = try XCTUnwrap(state.spaces.first(where: { $0.id == destination })?.selectedTab)
        XCTAssertEqual(moved.id, movedTab)
        XCTAssertEqual(moved.address, "https://example.com")
        XCTAssertFalse(state.spaces.first(where: { $0.id == source })!.tabs.contains(where: { $0.id == movedTab }))
        XCTAssertEqual(state.spaces.first(where: { $0.id == source })?.tabs.count, 1)
        XCTAssertEqual(state.pendingDataStoreDeletions, [])
        try state.validate()
    }

    func testInvalidTabGroupMoveDoesNotMutateState() throws {
        var state = NativeBrowserState()
        let original = state
        let tabID = try XCTUnwrap(state.selectedSpace?.selectedTabID)
        XCTAssertThrowsError(try state.moveTab(tabID, from: state.selectedSpaceID, to: UUID()))
        XCTAssertEqual(state, original)
        XCTAssertThrowsError(try state.reorderSpaces(fromOffsets: IndexSet(integer: 1), toOffset: 0))
        XCTAssertEqual(state, original)
    }

    func testHTTPSOnlyTopLevelNavigationAndCredentialFreeAddresses() throws {
        XCTAssertTrue(NativeBrowserAddress.mayLoadAsMainDocument(URL(string: "https://bank.example/")!))
        XCTAssertTrue(NativeBrowserAddress.mayLoadAsMainDocument(URL(string: "about:blank")!))
        XCTAssertFalse(NativeBrowserAddress.mayLoadAsMainDocument(URL(string: "http://bank.example/")!))
        XCTAssertFalse(NativeBrowserAddress.mayLoadAsMainDocument(URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(NativeBrowserAddress.mayLoadAsMainDocument(URL(string: "https://user:pass@bank.example/")!))
        XCTAssertEqual(
            NativeBrowserAddress.resolve("http://bank.example/login")?.absoluteString,
            "https://bank.example/login")
        XCTAssertNil(NativeBrowserAddress.resolve("https://user:secret@bank.example/"))
        XCTAssertNil(NativeBrowserAddress.resolve("ftp://bank.example/"))
    }

    func testInsecureNavigationCannotBePersistedInTabState() throws {
        var state = NativeBrowserState()
        let original = state
        let tabID = try XCTUnwrap(state.selectedSpace?.selectedTabID)
        XCTAssertThrowsError(try state.recordNavigation(tabID, address: "http://bank.example/", title: "Bank"))
        XCTAssertThrowsError(try state.recordNavigation(tabID, address: "data:text/html,test", title: "Bank"))
        XCTAssertEqual(state, original)
        try state.recordNavigation(tabID, address: "https://bank.example/", title: "Bank")
        try state.validate()
    }

    func testAddressBarRejectsUntrustedSchemesAndSearchesText() throws {
        XCTAssertEqual(NativeBrowserAddress.resolve("example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(NativeBrowserAddress.resolve("https://example.org/a")?.host, "example.org")
        XCTAssertEqual(NativeBrowserAddress.resolve("about:blank")?.absoluteString, "about:blank")
        XCTAssertEqual(NativeBrowserAddress.resolve("javascript:alert(1)")?.host, "duckduckgo.com")
        XCTAssertEqual(NativeBrowserAddress.resolve("two words")?.host, "duckduckgo.com")
        XCTAssertNil(NativeBrowserAddress.resolve("   "))
    }
}
