import CryptoKit
import Foundation
import WebKit

/// Compiles the pinned Brave iOS baseline as an Apple-native WebKit rule list.
/// No scripts, custom HTTP requests, browser extensions or background updater.
@MainActor
enum NativeContentBlocker {
    enum Failure: LocalizedError {
        case rulesMissing
        case rulesInvalid
        case storeUnavailable

        var errorDescription: String? {
            switch self {
            case .rulesMissing: "The bundled protection rules are missing."
            case .rulesInvalid: "The bundled protection rules are invalid."
            case .storeUnavailable: "WebKit's protection store is unavailable."
            }
        }
    }

    static func compileBundled() async throws -> WKContentRuleList {
        guard let url = Bundle.main.url(forResource: "BraveIOSProtection", withExtension: "json") else {
            throw Failure.rulesMissing
        }
        let data = try Data(contentsOf: url)
        guard let source = String(data: data, encoding: .utf8),
            let rules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            !rules.isEmpty
        else { throw Failure.rulesInvalid }
        guard let store = WKContentRuleListStore.default() else { throw Failure.storeUnavailable }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let identifier = "io.github.shipsen7.fennavio.native.brave-ios.\(digest)"
        if let cached = try? await store.lookUpContentRuleList(forIdentifier: identifier) { return cached }
        return try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: source)
    }
}
