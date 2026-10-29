import Foundation
import XCTest

@testable import FennavioNativePreview

final class NativePageLibraryTests: XCTestCase {
    func testVisitsAreHTTPSOnlyDeduplicatedAndBounded() throws {
        var library = NativePageLibrary()
        for index in 0..<520 {
            library.recordVisit(URL(string: "https://example.com/page/\(index)")!, title: "Page \(index)")
        }
        XCTAssertEqual(library.history.count, 500)
        XCTAssertEqual(library.history.first?.title, "Page 519")
        XCTAssertEqual(library.history.last?.title, "Page 20")
        library.recordVisit(URL(string: "https://example.com/page/519")!, title: "Updated")
        library.recordVisit(URL(string: "http://example.com/unsafe")!, title: "Unsafe")
        XCTAssertEqual(library.history.count, 500)
        XCTAssertEqual(library.history.first?.title, "Updated")
        try library.validate()
    }

    func testBookmarksPersistAndCorruptLibraryCannotBeOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = NativeBrowserStorage(fileURL: directory.appendingPathComponent("browser-state.json"))
        let bookmarkURL = try XCTUnwrap(URL(string: "https://bank.example/"))
        var library = NativePageLibrary()
        library.toggleBookmark(bookmarkURL, title: "Bank")
        library.recordVisit(bookmarkURL, title: "Bank")
        try storage.saveLibrary(library)
        XCTAssertEqual(try storage.loadLibrary(), library)

        let libraryFile = directory.appendingPathComponent("page-library.json")
        try "invalid-json".write(to: libraryFile, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try storage.loadLibrary())
        XCTAssertEqual(try String(contentsOf: libraryFile, encoding: .utf8), "invalid-json")
    }

    func testUnsupportedSchemaAndInsecureSavedPageAreRejected() throws {
        var library = NativePageLibrary()
        library.schemaVersion = 999
        XCTAssertThrowsError(try library.validate())

        library = NativePageLibrary()
        library.toggleBookmark(URL(string: "https://example.com/")!, title: "Example")
        let encoded = try JSONEncoder().encode(library)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var bookmarks = try XCTUnwrap(payload["bookmarks"] as? [[String: Any]])
        bookmarks[0]["address"] = "http://example.com/"
        payload["bookmarks"] = bookmarks
        let tampered = try JSONSerialization.data(withJSONObject: payload)
        let decoded = try JSONDecoder().decode(NativePageLibrary.self, from: tampered)
        XCTAssertThrowsError(try decoded.validate())
    }
}
