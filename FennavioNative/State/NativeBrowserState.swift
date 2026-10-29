import Foundation

/// Local browsing records. Website data belongs to WebKit's identifier-backed
/// data stores; this model contains no cookies, credentials, or private tabs.
struct NativeBrowserTab: Codable, Equatable, Identifiable {
    let id: UUID
    var address: String
    var title: String

    static func blank() -> Self {
        Self(id: UUID(), address: "about:blank", title: "New Tab")
    }
}

struct NativeBrowserSpace: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var tabs: [NativeBrowserTab]
    var selectedTabID: UUID

    static func make(name: String) -> Self {
        let tab = NativeBrowserTab.blank()
        return Self(id: UUID(), name: name, tabs: [tab], selectedTabID: tab.id)
    }

    var selectedTab: NativeBrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }
}

enum NativeBrowserStateError: LocalizedError {
    case invalidState
    case unsupportedVersion
    case missingSpace
    case missingTab
    case lastSpace

    var errorDescription: String? {
        switch self {
        case .invalidState: "Saved browsing data is inconsistent. No data was overwritten."
        case .unsupportedVersion: "Saved browsing data is from a newer version. No data was overwritten."
        case .missingSpace: "This Space is no longer available."
        case .missingTab: "This tab is no longer available."
        case .lastSpace: "At least one regular Space must remain."
        }
    }
}

struct NativeBrowserState: Codable, Equatable {
    var schemaVersion = 1
    private(set) var spaces: [NativeBrowserSpace]
    private(set) var selectedSpaceID: UUID
    /// A deletion is durable until WebKit confirms it removed the data store.
    private(set) var pendingDataStoreDeletions: [UUID]

    init() {
        let first = NativeBrowserSpace.make(name: "Personal")
        spaces = [first]
        selectedSpaceID = first.id
        pendingDataStoreDeletions = []
    }

    var selectedSpace: NativeBrowserSpace? {
        spaces.first { $0.id == selectedSpaceID }
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw NativeBrowserStateError.unsupportedVersion }
        guard !spaces.isEmpty, selectedSpace != nil else { throw NativeBrowserStateError.invalidState }
        let spaceIDs = spaces.map(\.id)
        guard Set(spaceIDs).count == spaceIDs.count else { throw NativeBrowserStateError.invalidState }
        let allTabIDs = spaces.flatMap { $0.tabs.map(\.id) }
        guard Set(allTabIDs).count == allTabIDs.count else { throw NativeBrowserStateError.invalidState }
        guard Set(pendingDataStoreDeletions).count == pendingDataStoreDeletions.count else {
            throw NativeBrowserStateError.invalidState
        }
        guard Set(spaceIDs).isDisjoint(with: pendingDataStoreDeletions) else {
            throw NativeBrowserStateError.invalidState
        }
        for space in spaces {
            for tab in space.tabs {
                guard let url = URL(string: tab.address),
                    url.absoluteString == "about:blank"
                        || (["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil)
                else { throw NativeBrowserStateError.invalidState }
            }
            guard !space.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !space.tabs.isEmpty,
                space.selectedTab != nil
            else { throw NativeBrowserStateError.invalidState }
        }
    }

    @discardableResult
    mutating func createSpace(name: String) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let space = NativeBrowserSpace.make(name: trimmed.isEmpty ? "Space \(spaces.count + 1)" : trimmed)
        spaces.append(space)
        selectedSpaceID = space.id
        return space.id
    }

    mutating func selectSpace(_ id: UUID) throws {
        guard spaces.contains(where: { $0.id == id }) else { throw NativeBrowserStateError.missingSpace }
        selectedSpaceID = id
    }

    mutating func renameSpace(_ id: UUID, to name: String) throws {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else {
            throw NativeBrowserStateError.missingSpace
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        spaces[index].name = trimmed
    }

    /// Reorder Spaces without changing their stable identities or tab ownership.
    mutating func reorderSpaces(fromOffsets offsets: IndexSet, toOffset destination: Int) throws {
        guard !offsets.isEmpty else { return }
        guard offsets.allSatisfy({ spaces.indices.contains($0) }), (0...spaces.count).contains(destination) else {
            throw NativeBrowserStateError.invalidState
        }
        let moved = offsets.map { spaces[$0] }
        for index in offsets.reversed() { spaces.remove(at: index) }
        let adjusted = destination - offsets.filter { $0 < destination }.count
        spaces.insert(contentsOf: moved, at: adjusted)
    }

    mutating func deleteSpace(_ id: UUID) throws {
        guard spaces.count > 1 else { throw NativeBrowserStateError.lastSpace }
        guard let index = spaces.firstIndex(where: { $0.id == id }) else {
            throw NativeBrowserStateError.missingSpace
        }
        spaces.remove(at: index)
        pendingDataStoreDeletions.append(id)
        if selectedSpaceID == id { selectedSpaceID = spaces[0].id }
    }

    @discardableResult
    mutating func newTab(in spaceID: UUID) throws -> UUID {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else {
            throw NativeBrowserStateError.missingSpace
        }
        let tab = NativeBrowserTab.blank()
        spaces[index].tabs.append(tab)
        spaces[index].selectedTabID = tab.id
        return tab.id
    }

    /// Move or reorder an ordered group of tabs without assigning new tab IDs.
    mutating func reorderTabs(in spaceID: UUID, fromOffsets offsets: IndexSet, toOffset destination: Int) throws {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else {
            throw NativeBrowserStateError.missingSpace
        }
        let count = spaces[index].tabs.count
        guard !offsets.isEmpty else { return }
        guard offsets.allSatisfy({ spaces[index].tabs.indices.contains($0) }), (0...count).contains(destination) else {
            throw NativeBrowserStateError.invalidState
        }
        let moved = offsets.map { spaces[index].tabs[$0] }
        for position in offsets.reversed() { spaces[index].tabs.remove(at: position) }
        let adjusted = destination - offsets.filter { $0 < destination }.count
        spaces[index].tabs.insert(contentsOf: moved, at: adjusted)
    }

    /// Preserve the moved tab's identity while changing its data-store ownership.
    /// A blank replacement prevents the source Space from having zero tabs.
    mutating func moveTab(_ tabID: UUID, from sourceID: UUID, to destinationID: UUID) throws {
        guard let source = spaces.firstIndex(where: { $0.id == sourceID }),
            let destination = spaces.firstIndex(where: { $0.id == destinationID })
        else { throw NativeBrowserStateError.missingSpace }
        guard sourceID != destinationID else { return }
        guard let tabIndex = spaces[source].tabs.firstIndex(where: { $0.id == tabID }) else {
            throw NativeBrowserStateError.missingTab
        }
        let tab = spaces[source].tabs.remove(at: tabIndex)
        if spaces[source].tabs.isEmpty { spaces[source].tabs.append(.blank()) }
        if spaces[source].selectedTabID == tabID {
            spaces[source].selectedTabID = spaces[source].tabs[min(tabIndex, spaces[source].tabs.count - 1)].id
        }
        spaces[destination].tabs.append(tab)
        spaces[destination].selectedTabID = tabID
    }

    mutating func selectTab(_ id: UUID, in spaceID: UUID) throws {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else {
            throw NativeBrowserStateError.missingSpace
        }
        guard spaces[index].tabs.contains(where: { $0.id == id }) else {
            throw NativeBrowserStateError.missingTab
        }
        spaces[index].selectedTabID = id
    }

    mutating func closeTab(_ id: UUID, in spaceID: UUID) throws {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else {
            throw NativeBrowserStateError.missingSpace
        }
        guard let tabIndex = spaces[index].tabs.firstIndex(where: { $0.id == id }) else {
            throw NativeBrowserStateError.missingTab
        }
        spaces[index].tabs.remove(at: tabIndex)
        if spaces[index].tabs.isEmpty { spaces[index].tabs.append(.blank()) }
        if spaces[index].selectedTabID == id {
            spaces[index].selectedTabID = spaces[index].tabs.last!.id
        }
    }

    mutating func recordNavigation(_ id: UUID, address: String, title: String) throws {
        guard let spaceIndex = spaces.firstIndex(where: { $0.tabs.contains(where: { $0.id == id }) }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == id })
        else { throw NativeBrowserStateError.missingTab }
        spaces[spaceIndex].tabs[tabIndex].address = address
        spaces[spaceIndex].tabs[tabIndex].title = title.isEmpty ? address : title
    }

    mutating func finishDataStoreDeletion(_ id: UUID) {
        pendingDataStoreDeletions.removeAll { $0 == id }
    }
}

/// Only load web URLs or a blank tab. Unrecognized schemes never execute from
/// the address bar, and free-form text becomes a search query.
enum NativeBrowserAddress {
    static func resolve(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value == "about:blank" { return URL(string: value) }
        if let components = URLComponents(string: value),
            ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
            let host = components.host, !host.isEmpty
        {
            return components.url
        }
        if !value.contains(where: \.isWhitespace), !value.contains(":") {
            let candidate = value == "localhost" || value.contains(".")
            if candidate, let url = URL(string: "https://\(value)"), url.host != nil {
                return url
            }
        }
        var query = URLComponents(string: "https://duckduckgo.com/")!
        query.queryItems = [URLQueryItem(name: "q", value: value)]
        return query.url
    }
}
