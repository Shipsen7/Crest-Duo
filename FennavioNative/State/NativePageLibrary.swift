import Foundation

/// Only regular-mode browsing data belongs here; never credentials or cookies.
struct NativeSavedPage: Codable, Equatable, Identifiable {
    let id: UUID
    var address: String
    var title: String
    var visitedAt: Date
}

struct NativePageLibrary: Codable, Equatable {
    var schemaVersion = 1
    private(set) var bookmarks: [NativeSavedPage] = []
    private(set) var history: [NativeSavedPage] = []

    private static let maximumHistoryItems = 500

    func validate() throws {
        guard schemaVersion == 1 else { throw NativeBrowserStateError.unsupportedVersion }
        guard bookmarks.count <= 10_000, history.count <= Self.maximumHistoryItems else {
            throw NativeBrowserStateError.limitExceeded
        }
        let ids = (bookmarks + history).map(\.id)
        guard Set(ids).count == ids.count else { throw NativeBrowserStateError.invalidState }
        for page in bookmarks + history {
            guard page.title.count <= 1_024, let url = URL(string: page.address), NativeBrowserAddress.isHTTPS(url)
            else {
                throw NativeBrowserStateError.invalidState
            }
        }
    }

    func isBookmarked(_ url: URL) -> Bool { bookmarks.contains { $0.address == url.absoluteString } }

    mutating func toggleBookmark(_ url: URL, title: String) {
        guard NativeBrowserAddress.isHTTPS(url) else { return }
        if let index = bookmarks.firstIndex(where: { $0.address == url.absoluteString }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.insert(
                NativeSavedPage(
                    id: UUID(), address: url.absoluteString, title: String(title.prefix(1_024)), visitedAt: .now),
                at: 0)
        }
    }

    mutating func recordVisit(_ url: URL, title: String, at date: Date = .now) {
        guard NativeBrowserAddress.isHTTPS(url) else { return }
        if history.first?.address == url.absoluteString {
            history[0].title = String(title.prefix(1_024))
            return
        }
        history.removeAll { $0.address == url.absoluteString }
        history.insert(
            NativeSavedPage(
                id: UUID(), address: url.absoluteString, title: String(title.prefix(1_024)), visitedAt: date),
            at: 0)
        if history.count > Self.maximumHistoryItems { history.removeLast(history.count - Self.maximumHistoryItems) }
    }

    mutating func clearHistory() { history.removeAll() }
}
