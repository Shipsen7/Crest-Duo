import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserFilterListRepositoryTests: XCTestCase {
    func testSubscriptionConvertsExceptionsAndKeepsCommittedRulesAfterFailedUpdate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FilterSubscriptionProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let sourceURL = try XCTUnwrap(URL(string: "https://filters.example/lists/main.txt"))
        FilterSubscriptionProtocol.response = """
            ! Test subscription
            ! 1
            ! 2
            ! 3
            ! 4
            ! 5
            ! 6
            ! 7
            ! 8
            ! 9
            ! 10
            !#if env_safari && !env_chromium
            ||advert.example^
            @@||advert.example/allowed.js$script
            example.org##.advertisement
            !#endif
            """
        FilterSubscriptionProtocol.response = FilterSubscriptionProtocol.response
            .replacingOccurrences(of: "\n", with: "\r\n")
        let repository = BrowserFilterListRepository(
            directory: directory, sourceURLs: [sourceURL], session: session, minimumRuleCount: 1
        )
        let candidate = try await repository.candidate(previousDigest: nil)
        let first = try XCTUnwrap(candidate)
        XCTAssertGreaterThan(first.ruleCount, 0)
        XCTAssertTrue(first.lists[0].source.contains("ignore-previous-rules"))
        XCTAssertTrue(first.lists[0].source.contains("css-display-none"))
        try await repository.commit(first)
        let unchanged = try await repository.candidate(previousDigest: first.inputDigest, force: false)
        XCTAssertNil(unchanged)
        FilterSubscriptionProtocol.response = "<html>upstream outage</html>"
        do {
            _ = try await repository.candidate(previousDigest: first.inputDigest)
            XCTFail("An invalid response must not replace protection")
        } catch BrowserFilterListError.invalidResponse {}
        let restored = try await repository.load()
        XCTAssertEqual(restored?.inputDigest, first.inputDigest)
        XCTAssertEqual(restored?.lists.first?.identifier, first.lists.first?.identifier)
        // Reject damaged storage instead of accepting altered rules under a trusted identifier.
        let file = directory.appendingPathComponent("Current.json")
        let damaged = try String(contentsOf: file, encoding: .utf8)
            .replacingOccurrences(of: "io.github.shipsen7.fennavio.protection.", with: "altered.")
        try Data(damaged.utf8).write(to: file)
        do {
            _ = try await repository.load()
            XCTFail("Damaged cached filters must be rejected")
        } catch BrowserFilterListError.invalidConversion {}
    }

    func testExpiryAndOfflineSelectionNeverFetchDisabledSources() async throws {
        XCTAssertEqual(
            BrowserFilterListRepository.updateInterval(in: "! Expires: 6 days (update frequency)"), 6 * 86_400)
        XCTAssertEqual(BrowserFilterListRepository.updateInterval(in: "! Diff-Expires: 317 minutes"), 5 * 86_400)
        XCTAssertEqual(BrowserFilterListRepository.updateInterval(in: "! Expires: 3 hours"), 3 * 3600)
        XCTAssertEqual(BrowserFilterListRepository.updateInterval(in: "! Expires: -1 days"), 5 * 86_400)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let included = try XCTUnwrap(URL(string: "https://filters.example/included.txt"))
        let excluded = "https://filters.example/excluded.txt"
        let sources = [
            included.absoluteString: "! Expires: 1 days\n||included.example^", excluded: "||excluded.example^",
        ]
        let repository = BrowserFilterListRepository(
            directory: directory, sourceURLs: [included], bundledSources: sources)
        let candidate = try await repository.candidate(previousDigest: nil, force: false, downloads: false)
        let selected = try XCTUnwrap(candidate)
        XCTAssertEqual(Set(selected.sources.keys), [included.absoluteString])
        XCTAssertTrue(selected.lists[0].source.contains("included"))
        XCTAssertFalse(selected.lists[0].source.contains("excluded"))
        try await repository.commit(selected)
        let empty = BrowserFilterListRepository(directory: directory.appendingPathComponent("empty"), sourceURLs: [])
        let noFilters = try await empty.candidate(previousDigest: nil, force: false, downloads: false)
        XCTAssertEqual(noFilters?.ruleCount, 0)
        XCTAssertEqual(noFilters?.lists.count, 0)
        try await empty.commit(try XCTUnwrap(noFilters))
        let restored = try await empty.load()
        XCTAssertEqual(restored?.lists.count, 0)
    }

    func testBundledSubscriptionCanBeSelectedOfflineWithItsIncludes() async throws {
        let sourceURL = try XCTUnwrap(Bundle.main.url(forResource: "FennavioFilterSources", withExtension: "json"))
        let sources = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: sourceURL))
        let root = try XCTUnwrap(
            URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = BrowserFilterListRepository(directory: directory, sourceURLs: [root], bundledSources: sources)
        let candidate = try await repository.candidate(previousDigest: nil, force: false, downloads: false)
        let selected = try XCTUnwrap(candidate)
        XCTAssertGreaterThan(selected.ruleCount, 1000)
        XCTAssertGreaterThan(selected.sources.count, 1)
        XCTAssertFalse(selected.sources.keys.contains { $0.contains("easylist-cookies") })
    }

    func testFilterConditionsRejectCodeAndPreserveBooleanSemantics() throws {
        XCTAssertTrue(try BrowserFilterCondition.evaluate("env_safari && (!env_chromium || env_firefox)"))
        XCTAssertFalse(try BrowserFilterCondition.evaluate("env_chromium || env_firefox && env_safari"))
        for invalid in ["", "env_safari)", "(env_safari", "env_safari; exit()", "env_safari &&"] {
            XCTAssertThrowsError(try BrowserFilterCondition.evaluate(invalid))
        }
    }
}

private final class FilterSubscriptionProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.response.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
