import Foundation

/// A locally selected source of WebKit filter rules. Browsing Spaces keep their
/// independent blocking policies and website data.
struct BrowserProtectionMode: Hashable, Sendable {
    // MARK: - Static Variables

    static let fennavio = BrowserProtectionMode(name: "fennavio")
    static let braveIOS = BrowserProtectionMode(name: "brave-ios")
    static let all = [fennavio, braveIOS]
    static let storageKey = "fennavio.protection.rule-source"

    // MARK: - Variables

    let name: String

    // MARK: - Initializers

    private init(name: String) { self.name = name }

    // MARK: - Actions - Selection

    static func named(_ name: String?) -> BrowserProtectionMode {
        all.first { $0.name == name } ?? .fennavio
    }

    static func selected(in defaults: UserDefaults = .standard) -> BrowserProtectionMode {
        named(defaults.string(forKey: storageKey))
    }
}
