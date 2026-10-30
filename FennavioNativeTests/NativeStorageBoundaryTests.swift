import Foundation
import XCTest

@testable import FennavioNativePreview

final class NativeStorageBoundaryTests: XCTestCase {
    private func withDirectory(_ test: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try test(folder)
    }

    func testMissingDataStartsEmptyButDirectoryIsNotTreatedAsMissing() throws {
        try withDirectory { folder in
            let storage = NativeBrowserStorage(fileURL: folder.appendingPathComponent("state.json"))
            try storage.load().validate()
            try FileManager.default.createDirectory(at: storage.fileURL, withIntermediateDirectories: true)
            XCTAssertThrowsError(try storage.load())
            XCTAssertThrowsError(try storage.save(NativeBrowserState()))
        }
    }

    func testSymlinkAndDanglingSymlinkCannotBeReadOrOverwritten() throws {
        try withDirectory { folder in
            let target = folder.appendingPathComponent("target.json")
            let sentinel = Data("preserve".utf8)
            try sentinel.write(to: target)
            let link = folder.appendingPathComponent("state.json")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let storage = NativeBrowserStorage(fileURL: link)
            XCTAssertThrowsError(try storage.load())
            XCTAssertThrowsError(try storage.save(NativeBrowserState()))
            XCTAssertEqual(try Data(contentsOf: target), sentinel)
            try FileManager.default.removeItem(at: target)
            XCTAssertThrowsError(try storage.load())
            XCTAssertThrowsError(try storage.save(NativeBrowserState()))
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        }
    }

    func testOversizedDataIsRejectedWithoutChangingIt() throws {
        try withDirectory { folder in
            let file = folder.appendingPathComponent("state.json")
            let data = Data(repeating: 32, count: NativeBrowserStorage.maximumFileBytes + 1)
            try data.write(to: file)
            XCTAssertThrowsError(try NativeBrowserStorage(fileURL: file).load())
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
    }

    func testLibrarySymlinkCannotOverwriteAnotherFile() throws {
        try withDirectory { folder in
            let target = folder.appendingPathComponent("target")
            try Data("keep".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(
                at: folder.appendingPathComponent("page-library.json"), withDestinationURL: target)
            let storage = NativeBrowserStorage(fileURL: folder.appendingPathComponent("state.json"))
            XCTAssertThrowsError(try storage.loadLibrary())
            XCTAssertThrowsError(try storage.saveLibrary(NativePageLibrary()))
            XCTAssertEqual(try Data(contentsOf: target), Data("keep".utf8))
        }
    }
}
