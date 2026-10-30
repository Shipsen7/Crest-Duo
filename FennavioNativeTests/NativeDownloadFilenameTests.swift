import Foundation
import XCTest

@testable import FennavioNativePreview

final class NativeDownloadFilenameTests: XCTestCase {
    func testFilenameCannotEscapeItsPrivateDirectory() {
        XCTAssertEqual(NativeDownloadFilename(suggested: "../../statement.pdf").value, "statement.pdf")
        let filename = NativeDownloadFilename(suggested: "a\\b:c\u{202E}\u{0000}.pdf").value
        XCTAssertFalse(filename.contains("\\"))
        XCTAssertFalse(filename.contains(":"))
        XCTAssertFalse(filename.contains("\u{202E}"))
        XCTAssertFalse(filename.contains("\u{0000}"))
    }

    func testLongUnicodeFilenamesAreBoundedInBytes() {
        let filename = NativeDownloadFilename(suggested: String(repeating: "🧑‍💻", count: 200)).value
        XCTAssertFalse(filename.isEmpty)
        XCTAssertLessThanOrEqual(filename.utf8.count, 180)
    }

    func testEmptyAndDotNamesHaveSafeFallback() {
        for name in ["", " ", ".", "..", "...."] {
            XCTAssertEqual(NativeDownloadFilename(suggested: name).value, "Download")
        }
    }
}
