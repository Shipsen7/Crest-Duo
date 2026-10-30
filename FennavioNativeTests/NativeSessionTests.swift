#if canImport(UIKit) && canImport(WebKit)
    import Foundation
    import WebKit
    import XCTest

    @testable import FennavioNativePreview

    final class NativeSessionTests: XCTestCase {
        @MainActor
        private func fixture() throws -> (URL, NativeBrowserSession, NativeBrowserStorage) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let storage = NativeBrowserStorage(fileURL: directory.appendingPathComponent("state.json"))
            let session = try NativeBrowserSession(
                storage: storage, downloadDirectory: directory.appendingPathComponent("downloads"))
            return (directory, session, storage)
        }

        @MainActor
        func testPrivateTabsNeverReachPersistentStateAndEndWithNewStore() throws {
            let (directory, session, storage) = try fixture()
            defer { try? FileManager.default.removeItem(at: directory) }
            session.createSpace(name: "Regular")
            let normalState = try storage.load()
            let regular = try XCTUnwrap(session.webView(for: session.selectedTabID))
            XCTAssertTrue(regular.configuration.websiteDataStore.isPersistent)
            session.switchToPrivate()
            let privatePage = try XCTUnwrap(session.webView(for: session.selectedTabID))
            let privateID = session.selectedTabID
            XCTAssertFalse(privatePage.configuration.websiteDataStore.isPersistent)
            XCTAssertFalse(privatePage.configuration.websiteDataStore === regular.configuration.websiteDataStore)
            session.newTab()
            let secondPrivate = try XCTUnwrap(session.webView(for: session.selectedTabID))
            XCTAssertTrue(privatePage.configuration.websiteDataStore === secondPrivate.configuration.websiteDataStore)
            XCTAssertEqual(try storage.load(), normalState)
            session.endPrivateSession()
            XCTAssertNil(privatePage.navigationDelegate)
            XCTAssertNil(privatePage.uiDelegate)
            XCTAssertFalse(session.privateTabs.contains(where: { $0.id == privateID }))
            session.switchToPrivate()
            let replacement = try XCTUnwrap(session.webView(for: session.selectedTabID))
            XCTAssertFalse(replacement.configuration.websiteDataStore === privatePage.configuration.websiteDataStore)
            XCTAssertEqual(try storage.load(), normalState)
            XCTAssertTrue(try storage.loadLibrary().history.isEmpty)
        }

        @MainActor
        func testMoveKeepsRuntimeAndGroupDeletionKeepsOtherPages() throws {
            let (directory, session, _) = try fixture()
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = session.selectedSpaceID
            let tabID = session.selectedTabID
            let page = try XCTUnwrap(session.webView(for: tabID))
            session.createSpace(name: "Reading")
            let destination = session.selectedSpaceID
            session.switchToSpace(source)
            session.moveTab(tabID, to: destination)
            session.switchToSpace(destination)
            XCTAssertTrue(session.webView(for: tabID) === page)
            session.deleteSpace(source)
            XCTAssertTrue(session.webView(for: tabID) === page)
            XCTAssertTrue(session.state.pendingDataStoreDeletions.isEmpty)
            XCTAssertNil(session.currentHost)  // A blank/failed page has no TLS indicator.
        }

        @MainActor
        func testClosedOrBackgroundTabCannotPresentInteraction() throws {
            let (directory, session, _) = try fixture()
            defer { try? FileManager.default.removeItem(at: directory) }
            let tabID = session.selectedTabID
            let page = try XCTUnwrap(session.webView(for: tabID))
            XCTAssertTrue(session.allowsInteraction(from: tabID))
            session.setForeground(false)
            XCTAssertFalse(session.allowsInteraction(from: tabID))
            session.setForeground(true)
            session.newTab()
            XCTAssertFalse(session.allowsInteraction(from: tabID))
            session.closeTab(tabID)
            let state = session.state
            session.pageDidChange(tabID, page: page)
            XCTAssertEqual(session.state, state)
            XCTAssertNil(page.navigationDelegate)
            XCTAssertNil(page.uiDelegate)
        }

        @MainActor
        func testBundledBlockerCompilesInWebKit() async throws {
            let rules = try await NativeContentBlocker.compileBundled()
            XCTAssertFalse(rules.identifier.isEmpty)
        }
    }
#endif
