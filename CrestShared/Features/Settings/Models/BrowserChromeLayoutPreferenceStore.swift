import Foundation
import Observation

// MARK: - Types

/// The three independent positions in a browser window.
enum BrowserChromeBarPosition: String, Codable, CaseIterable, Sendable {
    case top
    case bottom
}

/// Whether the horizontal tab strip is always shown or opened when requested.
enum BrowserChromeTabStripVisibility: String, Codable, CaseIterable, Sendable {
    case always
    case onDemand
}

/// Whether a bar stays in place or contracts as a page scrolls.
enum BrowserChromeScrollBehavior: String, Codable, CaseIterable, Sendable {
    case alwaysVisible
    case collapsesOnScroll
}

/// The glass-like or less translucent browser chrome.
enum BrowserChromeVisualStyle: String, Codable, CaseIterable, Sendable {
    case glass
    case calm
}

/// Device-local choices. These do not belong to a Space and never enter sync.
struct BrowserChromeLayoutOptions: Codable, Hashable, Sendable {
    // MARK: - Static Variables

    static let compactDefault = BrowserChromeLayoutOptions(
        addressPosition: .bottom, navigationPosition: .bottom, tabStripPosition: .bottom,
        tabStripVisibility: .onDemand)
    static let expandedDefault = BrowserChromeLayoutOptions(
        addressPosition: .bottom, navigationPosition: .bottom, tabStripPosition: .bottom,
        tabStripVisibility: .always)
    static let tabletDefault = expandedDefault
    static let desktopDefault = BrowserChromeLayoutOptions(
        addressPosition: .top, navigationPosition: .top, tabStripPosition: .top,
        tabStripVisibility: .always)

    // MARK: - Variables

    var addressPosition: BrowserChromeBarPosition
    var navigationPosition: BrowserChromeBarPosition
    var tabStripPosition: BrowserChromeBarPosition
    var tabStripVisibility: BrowserChromeTabStripVisibility
    var addressScroll: BrowserChromeScrollBehavior
    var navigationScroll: BrowserChromeScrollBehavior
    var tabStripScroll: BrowserChromeScrollBehavior
    var visualStyle: BrowserChromeVisualStyle

    // MARK: - Initializers

    init(
        addressPosition: BrowserChromeBarPosition,
        navigationPosition: BrowserChromeBarPosition,
        tabStripPosition: BrowserChromeBarPosition,
        tabStripVisibility: BrowserChromeTabStripVisibility,
        addressScroll: BrowserChromeScrollBehavior = .alwaysVisible,
        navigationScroll: BrowserChromeScrollBehavior = .alwaysVisible,
        tabStripScroll: BrowserChromeScrollBehavior = .alwaysVisible,
        visualStyle: BrowserChromeVisualStyle = .glass
    ) {
        self.addressPosition = addressPosition
        self.navigationPosition = navigationPosition
        self.tabStripPosition = tabStripPosition
        self.tabStripVisibility = tabStripVisibility
        self.addressScroll = addressScroll
        self.navigationScroll = navigationScroll
        self.tabStripScroll = tabStripScroll
        self.visualStyle = visualStyle
    }
}

/// A fixed device-layout context, not a size-class proxy. The mobile shell
/// resolves which context is active; the Mac uses `mac`.
struct BrowserChromeDeviceProfile: Hashable, Sendable {
    // MARK: - Static Variables

    static let duoFolded = BrowserChromeDeviceProfile(
        key: "duo-folded", defaults: .compactDefault)
    static let duoUnfolded = BrowserChromeDeviceProfile(
        key: "duo-unfolded", defaults: .expandedDefault)
    static let iPad = BrowserChromeDeviceProfile(
        key: "ipad", defaults: .tabletDefault)
    static let mac = BrowserChromeDeviceProfile(
        key: "mac", defaults: .desktopDefault)
    static let all = [duoFolded, duoUnfolded, iPad, mac]

    // MARK: - Variables

    let key: String
    let defaults: BrowserChromeLayoutOptions

    // MARK: - Actions - Resolution

    /// A non-foldable phone uses the compact controls. Only a display the
    /// platform identifies as the inner foldable display uses Duo expanded.
    static func mobile(isTablet: Bool, isInnerFoldableDisplay: Bool) -> BrowserChromeDeviceProfile {
        if isTablet { return .iPad }
        return isInnerFoldableDisplay ? .duoUnfolded : .duoFolded
    }
}

/// Persists layout preferences only in this installation's UserDefaults.
/// Space selection, private browsing, cookies and CloudKit are not consulted.
@MainActor @Observable
final class BrowserChromeLayoutPreferenceStore {
    // MARK: - Static Variables

    static let shared = BrowserChromeLayoutPreferenceStore()
    static let storageKeyPrefix = "fennavio.chrome.layout-profile.v1."

    // MARK: - Variables

    private(set) var configurations: [String: BrowserChromeLayoutOptions]
    @ObservationIgnored private let defaults: UserDefaults

    // MARK: - Initializers

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded: [String: BrowserChromeLayoutOptions] = [:]
        for profile in BrowserChromeDeviceProfile.all {
            guard let data = defaults.data(forKey: Self.storageKey(for: profile)),
                let options = try? JSONDecoder().decode(BrowserChromeLayoutOptions.self, from: data)
            else { continue }
            loaded[profile.key] = options
        }
        configurations = loaded
    }

    // MARK: - Actions - Preferences

    func options(for profile: BrowserChromeDeviceProfile) -> BrowserChromeLayoutOptions {
        configurations[profile.key] ?? profile.defaults
    }

    /// Replace one context without resetting or changing any other context.
    func set(_ options: BrowserChromeLayoutOptions, for profile: BrowserChromeDeviceProfile) {
        guard options != self.options(for: profile) else { return }
        configurations[profile.key] = options
        save(options, for: profile)
    }

    func restoreDefaults(for profile: BrowserChromeDeviceProfile) {
        guard configurations.removeValue(forKey: profile.key) != nil else { return }
        defaults.removeObject(forKey: Self.storageKey(for: profile))
    }

    // MARK: - Actions - Persistence

    private static func storageKey(for profile: BrowserChromeDeviceProfile) -> String {
        storageKeyPrefix + profile.key
    }

    private func save(_ options: BrowserChromeLayoutOptions, for profile: BrowserChromeDeviceProfile) {
        guard let data = try? JSONEncoder().encode(options) else { return }
        defaults.set(data, forKey: Self.storageKey(for: profile))
    }
}
