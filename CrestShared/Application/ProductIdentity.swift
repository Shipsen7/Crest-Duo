import Foundation

enum ProductIdentity {
    // MARK: - Static Variables

    static let name = "Fennavio"
    static let bundleIdentifier = "io.github.shipsen7.fennavio"
    static let serviceNamespace = bundleIdentifier
    static let storageDirectoryName = name

    /// Private builds have no publisher or trusted update feed. Enabling a
    /// feed requires separate review of the fork's own signing and update keys.
    static let softwareUpdateFeedBaseURL: URL? = nil
}
