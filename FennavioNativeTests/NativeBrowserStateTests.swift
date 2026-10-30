import Foundation
import XCTest

@testable import FennavioNativePreview

final class NativeBrowserStateTests: XCTestCase {
    func testSpacesKeepIndependentTabOwnershipAndSelection() throws {
        var state = NativeBrowserState()
        let original = state.selectedSpaceID
        let originalTab = try XCTUnwrap(state.selectedSpace?.selectedTabID)
        let second = state.createSpace(name: "Reading")
        let secondTab = try state.newTab(in: second)
        try state.selectSpace(original)
        XCTAssertEqual(state.selectedSpace?.selectedTabID, originalTab)
        XCTAssertEqual(state.spaces.first { $0.id == second }?.selectedTabID, secondTab)
        XCTAssertNotEqual(originalTab, secondTab)
        try state.validate()
    }

    func testDeletingGroupDoesNotDeleteSharedWebsiteStore() throws {
        var state = NativeBrowserState()
        let original = state.selectedSpaceID
        _ = state.createSpace(name: "Work")
        try state.deleteSpace(original)
        XCTAssertFalse(state.spaces.contains { $0.id == original })
        XCTAssertTrue(state.pendingDataStoreDeletions.isEmpty)
        try state.validate()
    }

    func testLegacyStoreDeletionRemainsDurableUntilConfirmed() throws {
        let id = UUID()
        var payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(NativeBrowserState())) as? [String: Any])
        payload["pendingDataStoreDeletions"] = [id.uuidString]
        var state = try JSONDecoder().decode(
            NativeBrowserState.self, from: JSONSerialization.data(withJSONObject: payload))
        try state.validate()
        XCTAssertEqual(state.pendingDataStoreDeletions, [id])
        state.finishDataStoreDeletion(id)
        XCTAssertTrue(state.pendingDataStoreDeletions.isEmpty)
    }

    func testCannotDeleteLastSpace() {
        var state = NativeBrowserState()
        XCTAssertThrowsError(try state.deleteSpace(state.selectedSpaceID))
        XCTAssertEqual(state.spaces.count, 1)
    }

    func testClosingLastTabReplacesItWithNewBlankTab() throws {
        var state = NativeBrowserState()
        let id = try XCTUnwrap(state.selectedSpace?.selectedTabID)
        try state.closeTab(id, in: state.selectedSpaceID)
        XCTAssertEqual(state.selectedSpace?.tabs.count, 1)
        XCTAssertEqual(state.selectedSpace?.selectedTab?.address, "about:blank")
        XCTAssertNotEqual(state.selectedSpace?.selectedTabID, id)
        try state.validate()
    }

    func testStatePersistsAndCorruptionDoesNotGetOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        let storage = NativeBrowserStorage(fileURL: file)
        var state = NativeBrowserState()
        _ = state.createSpace(name: "Books")
        try storage.save(state)
        XCTAssertEqual(try storage.load(), state)
        try Data("not-json".utf8).write(to: file)
        XCTAssertThrowsError(try storage.load())
        XCTAssertEqual(try Data(contentsOf: file), Data("not-json".utf8))
    }

    func testUnsupportedStoredSchemaCannotBeLoaded() {
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
        let id = try XCTUnwrap(state.selectedSpace?.selectedTabID)
        try state.recordNavigation(id, address: "https://example.com", title: "Example")
        let destination = state.createSpace(name: "Reading")
        try state.moveTab(id, from: source, to: destination)
        let moved = try XCTUnwrap(state.spaces.first { $0.id == destination }?.selectedTab)
        XCTAssertEqual(moved.id, id)
        XCTAssertEqual(moved.address, "https://example.com")
        XCTAssertEqual(state.spaces.first { $0.id == source }?.tabs.count, 1)
        XCTAssertFalse(state.spaces.first { $0.id == source }!.tabs.contains { $0.id == id })
        XCTAssertTrue(state.pendingDataStoreDeletions.isEmpty)
        try state.validate()
    }

    func testInvalidTabGroupMoveDoesNotMutateState() throws {
        var state = NativeBrowserState()
        let original = state
        let id = try XCTUnwrap(state.selectedSpace?.selectedTabID)
        XCTAssertThrowsError(try state.moveTab(id, from: state.selectedSpaceID, to: UUID()))
        XCTAssertEqual(state, original)
        XCTAssertThrowsError(try state.reorderSpaces(fromOffsets: IndexSet(integer: 1), toOffset: 0))
        XCTAssertEqual(state, original)
    }

    func testHTTPSOnlyTopLevelNavigationAndCredentialFreeAddresses() {
        for address in ["https://bank.example/", "about:blank"] {
            XCTAssertTrue(NativeBrowserAddress.mayLoadAsMainDocument(URL(string: address)!))
        }
        for address in [
            "http://bank.example/", "file:///etc/passwd", "https://user:pass@bank.example/", "data:text/html,bank",
        ] {
            XCTAssertFalse(NativeBrowserAddress.mayLoadAsMainDocument(URL(string: address)!))
        }
        XCTAssertEqual(
            NativeBrowserAddress.resolve("http://bank.example/login")?.absoluteString, "https://bank.example/login")
        XCTAssertNil(NativeBrowserAddress.resolve("https://user:secret@bank.example/"))
        XCTAssertNil(NativeBrowserAddress.resolve("ftp://bank.example/"))
    }

    func testInsecureNavigationCannotBePersistedInTabState() throws {
        var state = NativeBrowserState()
        let original = state
        let id = try XCTUnwrap(state.selectedSpace?.selectedTabID)
        XCTAssertThrowsError(try state.recordNavigation(id, address: "http://bank.example/", title: "Bank"))
        XCTAssertThrowsError(try state.recordNavigation(id, address: "data:text/html,test", title: "Bank"))
        XCTAssertEqual(state, original)
        try state.recordNavigation(id, address: "https://bank.example/", title: "Bank")
        try state.validate()
    }

    func testExplicitSchemesAndCredentialsNeverBecomeSearchQueries() {
        for input in [
            "javascript:alert(1)", "data:text/html,test", "file:///secret", "user:secret@bank.example",
            "mailto:user@example.com",
        ] {
            XCTAssertNil(NativeBrowserAddress.resolve(input), input)
        }
        XCTAssertEqual(NativeBrowserAddress.resolve("example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(NativeBrowserAddress.resolve("two words")?.host, "duckduckgo.com")
        XCTAssertEqual(NativeBrowserAddress.resolve("about:blank")?.absoluteString, "about:blank")
        XCTAssertNil(NativeBrowserAddress.resolve("   "))
    }

    func testAddressBoundsAndControlCharacters() {
        XCTAssertNil(NativeBrowserAddress.resolve("https://bank.example/\nother"))
        XCTAssertNil(NativeBrowserAddress.resolve("https://bank.example/\u{202E}txt"))
        XCTAssertNil(NativeBrowserAddress.resolve("https://bank.example:70000/"))
        XCTAssertNil(NativeBrowserAddress.resolve(String(repeating: "a", count: 8_193)))
        XCTAssertFalse(NativeBrowserAddress.isHTTPS(URL(string: "about:blank")!))
    }

    func testTabNamesAreBoundedAndExcessTabsCannotBeSaved() throws {
        var state = NativeBrowserState()
        let id = try XCTUnwrap(state.selectedSpace?.selectedTabID)
        try state.recordNavigation(id, address: "https://example.com/", title: String(repeating: "a", count: 5_000))
        XCTAssertEqual(state.selectedSpace?.selectedTab?.title.count, 1_024)
        for _ in 0..<1_000 { _ = try state.newTab(in: state.selectedSpaceID) }
        XCTAssertThrowsError(try state.validate())
    }
}
