import ContentBlockerConverter
import CryptoKit
import Foundation

// MARK: - Types

struct BrowserFilterRuleSet: Codable, Sendable {
    let updatedAt: Date
    let inputDigest: String
    let ruleCount: Int
    let lists: [List]
    /// Keep the corresponding upstream source with the locally converted data.
    let sources: [String: String]
    var sourceDates: [String: Date]? = nil

    struct List: Codable, Sendable {
        let identifier: String
        let source: String
    }
}

enum BrowserFilterListError: Error {
    case invalidResponse
    case invalidCondition
    case invalidConversion
}

/// Downloads public filter data without any browser profile, then converts it
/// away from the main actor. Only a fully compiled candidate may be committed.
actor BrowserFilterListRepository {
    // MARK: - Variables

    private let session: URLSession
    private let directory: URL
    private let sourceURLs: [URL]
    private let minimumRuleCount: Int
    private let bundledSources: [String: String]

    // MARK: - Initializers

    init(
        directory: URL, sourceURLs: [URL], session: URLSession? = nil, minimumRuleCount: Int = 1,
        bundledSources: [String: String] = [:]
    ) {
        self.bundledSources = bundledSources
        self.directory = directory
        self.sourceURLs = sourceURLs
        self.minimumRuleCount = minimumRuleCount
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        self.session = session ?? URLSession(configuration: configuration)
    }

    // MARK: - Actions - Persistence

    func load() throws -> BrowserFilterRuleSet? {
        let file = directory.appendingPathComponent("Current.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let snapshot = try JSONDecoder().decode(BrowserFilterRuleSet.self, from: Data(contentsOf: file))
        try validate(snapshot)
        return snapshot
    }

    func lastCheck() -> Date? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("LastCheck.json")) else { return nil }
        return try? JSONDecoder().decode(Date.self, from: data)
    }

    func recordCheck() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(Date()).write(
            to: directory.appendingPathComponent("LastCheck.json"), options: .atomic)
    }

    func commit(_ snapshot: BrowserFilterRuleSet) throws {
        try validate(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent("Current.json"), options: .atomic)
    }

    // MARK: - Actions - Updating

    func candidate(previousDigest: String?, force: Bool = true, downloads: Bool = true) async throws
        -> BrowserFilterRuleSet?
    {
        let previous = try? load()
        let savedSources = previous?.sources ?? bundledSources
        let savedDates = previous?.sourceDates ?? [:]
        var dates: [String: Date] = [:]
        var sources: [String: String] = [:]
        var lines: [String] = []
        var seen = Set<String>()
        for url in sourceURLs {
            for line in try await expand(
                url, ancestry: [], sources: &sources, dates: &dates,
                savedSources: savedSources, savedDates: savedDates, force: force, downloads: downloads)
            where seen.insert(line).inserted {
                lines.append(line)
            }
        }
        let digest = Self.digest(lines.joined(separator: "\n"))
        if digest == previousDigest, dates == previous?.sourceDates { return nil }
        if digest == previous?.inputDigest, let previous {
            return BrowserFilterRuleSet(
                updatedAt: previous.updatedAt, inputDigest: digest, ruleCount: previous.ruleCount,
                lists: previous.lists, sources: sources, sourceDates: dates)
        }
        let exceptions = lines.filter { line in
            line.hasPrefix("@@")
                || ["#@#", "#@?#", "#@$#", "#@%#", "$badfilter", ",badfilter"].contains {
                    line.contains($0)
                }
        }
        let exceptionSet = Set(exceptions)
        let ordinary = lines.filter { !exceptionSet.contains($0) }
        var lists: [BrowserFilterRuleSet.List] = []
        var count = 0
        for start in stride(from: 0, to: ordinary.count, by: 60_000) {
            try Task.checkCancellation()
            let result = ContentBlockerConverter().convertArray(
                rules: Array(ordinary[start..<min(start + 60_000, ordinary.count)]) + exceptions,
                safariVersion: .safari26,
                advancedBlocking: false
            )
            guard result.discardedSafariRules == 0, result.safariRulesCount > 0 else {
                throw BrowserFilterListError.invalidConversion
            }
            count += result.safariRulesCount
            lists.append(
                .init(identifier: Self.identifier(for: result.safariRulesJSON), source: result.safariRulesJSON))
        }
        guard sourceURLs.isEmpty || count >= minimumRuleCount, lists.count <= 16 else {
            throw BrowserFilterListError.invalidConversion
        }
        return BrowserFilterRuleSet(
            updatedAt: Date(), inputDigest: digest, ruleCount: count, lists: lists, sources: sources, sourceDates: dates
        )
    }

    private func expand(
        _ url: URL, ancestry: [URL], sources: inout [String: String], dates: inout [String: Date],
        savedSources: [String: String], savedDates: [String: Date], force: Bool, downloads: Bool
    ) async throws -> [String] {
        guard url.scheme == "https", !ancestry.contains(url), ancestry.count < 8, sources.count < 40 else {
            throw BrowserFilterListError.invalidResponse
        }
        let text: String
        if let saved = sources[url.absoluteString] {
            text = saved
        } else if let saved = savedSources[url.absoluteString],
            !downloads
                || (!force
                    && savedDates[url.absoluteString].map {
                        Date().timeIntervalSince($0) < Self.updateInterval(in: saved)
                    } == true)
        {
            text = saved
            sources[url.absoluteString] = saved
            dates[url.absoluteString] = savedDates[url.absoluteString] ?? .distantPast
        } else {
            guard downloads else { throw BrowserFilterListError.invalidResponse }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.httpShouldHandleCookies = false
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                response.url == url, response.expectedContentLength <= 16_000_000
            else { throw BrowserFilterListError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 16_000_000 else { throw BrowserFilterListError.invalidResponse }
                data.append(byte)
            }
            guard let decoded = String(data: data, encoding: .utf8),
                !decoded.prefix(256).lowercased().contains("<html"),
                decoded.contains("!"), decoded.components(separatedBy: .newlines).count > 10
            else { throw BrowserFilterListError.invalidResponse }
            text = decoded.replacingOccurrences(of: "\u{feff}", with: "")
            guard sources.values.reduce(data.count, { $0 + $1.utf8.count }) <= 64_000_000 else {
                throw BrowserFilterListError.invalidResponse
            }
            sources[url.absoluteString] = text
            dates[url.absoluteString] = Date()
        }
        var active = true
        var stack: [(parent: Bool, condition: Bool)] = []
        var result: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("!#if ") {
                let condition = try BrowserFilterCondition.evaluate(String(line.dropFirst(5)))
                stack.append((active, condition))
                active = active && condition
            } else if line == "!#else" {
                guard let branch = stack.last else { throw BrowserFilterListError.invalidCondition }
                active = branch.parent && !branch.condition
            } else if line == "!#endif" {
                guard let branch = stack.popLast() else { throw BrowserFilterListError.invalidCondition }
                active = branch.parent
            } else if active, line.hasPrefix("!#include ") {
                let parent = url.deletingLastPathComponent().absoluteString
                guard let child = URL(string: String(line.dropFirst(10)), relativeTo: url)?.absoluteURL.standardized,
                    child.absoluteString.hasPrefix(parent), child.host == url.host,
                    child.user == nil, child.password == nil, child.query == nil, child.fragment == nil
                else { throw BrowserFilterListError.invalidResponse }
                result += try await expand(
                    child, ancestry: ancestry + [url], sources: &sources, dates: &dates,
                    savedSources: savedSources, savedDates: savedDates, force: force, downloads: downloads)
            } else if active, !line.isEmpty, !line.hasPrefix("!"), !line.hasPrefix("[") {
                result.append(line)
            }
        }
        guard stack.isEmpty else { throw BrowserFilterListError.invalidCondition }
        return result
    }

    /// Full downloads follow Expires, not the unrelated differential-update protocol.
    /// Missing metadata follows uBlock's five-day default. Bound untrusted values.
    static func updateInterval(in source: String) -> TimeInterval {
        for raw in source.components(separatedBy: .newlines).prefix(64) {
            let line = raw.trimmingCharacters(in: .whitespaces).lowercased()
            guard line.hasPrefix("! expires:") else { continue }
            let parts = line.dropFirst(10).split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, let amount = Double(parts[0]), amount.isFinite, amount > 0 else { continue }
            let unit = parts[1]
            let multiplier: Double
            if unit.hasPrefix("day") {
                multiplier = 86_400
            } else if unit.hasPrefix("hour") {
                multiplier = 3600
            } else if unit.hasPrefix("minute") {
                multiplier = 60
            } else {
                continue
            }
            return min(7 * 86_400, max(3600, amount * multiplier))
        }
        return 5 * 86_400
    }

    // MARK: - Actions - Integrity

    static func identifier(for source: String) -> String {
        "io.github.shipsen7.fennavio.protection.\(digest(source))"
    }

    private static func digest(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func validate(_ snapshot: BrowserFilterRuleSet) throws {
        guard sourceURLs.isEmpty || !snapshot.lists.isEmpty, snapshot.lists.count <= 16,
            sourceURLs.isEmpty || snapshot.ruleCount >= minimumRuleCount,
            snapshot.lists.allSatisfy({ $0.identifier == Self.identifier(for: $0.source) })
        else { throw BrowserFilterListError.invalidConversion }
    }
}
