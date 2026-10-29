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

    func testAddressBarRejectsUntrustedSchemesAndSearchesText() throws {
        XCTAssertEqual(NativeBrowserAddress.resolve("example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(NativeBrowserAddress.resolve("https://example.org/a")?.host, "example.org")
        XCTAssertEqual(NativeBrowserAddress.resolve("about:blank")?.absoluteString, "about:blank")
        XCTAssertEqual(NativeBrowserAddress.resolve("javascript:alert(1)")?.host, "duckduckgo.com")
        XCTAssertEqual(NativeBrowserAddress.resolve("two words")?.host, "duckduckgo.com")
        XCTAssertNil(NativeBrowserAddress.resolve("   "))
    }
}
