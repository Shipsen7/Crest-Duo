import Foundation
import Observation

/// Device-local appearance choices. Private browsing uses a separate in-memory
/// instance, and a profile can never read another profile's enabled origins.
@MainActor
@Observable
final class MobileWebsiteDarkModePreferences {
    // MARK: - Types

    private struct Entry: Codable, Hashable {
        let profileID: UUID
        let origin: String
    }

    // MARK: - Static Variables

    private static let key = "fennavio.websites.dark-mode.v1"
    static let shared = MobileWebsiteDarkModePreferences(
        defaults: BrowserLaunchEnvironment.current.requiresIsolation ? nil : .standard
    )

    // MARK: - Variables

    private var entries: Set<Entry>
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let observers = NSHashTable<MobileWebPageDarkMode>.weakObjects()

    // MARK: - Initializers

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        let saved = defaults.flatMap { $0.data(forKey: Self.key) }
        entries = saved.flatMap {
            try? JSONDecoder().decode(Set<Entry>.self, from: $0)
        } ?? []
    }

    // MARK: - Actions - Appearance

    func isEnabled(for origin: SiteOrigin, in profileID: UUID) -> Bool {
        entries.contains(Entry(profileID: profileID, origin: origin.displayName))
    }

    func enabledOrigins(in profileID: UUID) -> [String] {
        entries.filter { $0.profileID == profileID }.map(\.origin).sorted()
    }

    func setEnabled(_ enabled: Bool, for origin: SiteOrigin, in profileID: UUID) {
        let entry = Entry(profileID: profileID, origin: origin.displayName)
        if enabled { entries.insert(entry) } else { entries.remove(entry) }
        persistAndNotify()
    }

    func removeProfile(_ profileID: UUID) {
        entries = entries.filter { $0.profileID != profileID }
        persistAndNotify()
    }

    func register(_ observer: MobileWebPageDarkMode) {
        observers.add(observer)
        observer.preferencesDidChange()
    }

    private func persistAndNotify() {
        if let data = try? JSONEncoder().encode(entries) { defaults?.set(data, forKey: Self.key) }
        for observer in observers.allObjects { observer.preferencesDidChange() }
    }
}
