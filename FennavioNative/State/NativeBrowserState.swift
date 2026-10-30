import Foundation

/// Regular groups share WebKit's cookie store. These records contain no
/// credentials, cookies or private tabs.
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

    var selectedTab: NativeBrowserTab? { tabs.first { $0.id == selectedTabID } }
}

enum NativeBrowserStateError: LocalizedError {
    case invalidState, unsupportedVersion, missingSpace, missingTab, lastSpace, limitExceeded

    var errorDescription: String? {
        switch self {
        case .invalidState: "Saved browsing data is inconsistent. No data was overwritten."
        case .unsupportedVersion: "Saved browsing data is from a newer version. No data was overwritten."
        case .missingSpace: "This Space is no longer available."
        case .missingTab: "This tab is no longer available."
        case .lastSpace: "At least one regular Space must remain."
        case .limitExceeded: "The local browsing-data limit was reached. Close unused tabs or groups first."
        }
    }
}

struct NativeBrowserState: Codable, Equatable {
    var schemaVersion = 1
    private(set) var spaces: [NativeBrowserSpace]
    private(set) var selectedSpaceID: UUID
    /// Compatibility with earlier native previews that used identified stores.
    /// New groups use the shared default store and never add deletion requests.
    private(set) var pendingDataStoreDeletions: [UUID]

    init() {
        let first = NativeBrowserSpace.make(name: "Personal")
        spaces = [first]
        selectedSpaceID = first.id
        pendingDataStoreDeletions = []
    }

    var selectedSpace: NativeBrowserSpace? { spaces.first { $0.id == selectedSpaceID } }

    func validate() throws {
        guard schemaVersion == 1 else { throw NativeBrowserStateError.unsupportedVersion }
        guard spaces.count <= 100, spaces.reduce(0, { $0 + $1.tabs.count }) <= 1_000,
            pendingDataStoreDeletions.count <= 1_000
        else { throw NativeBrowserStateError.limitExceeded }
        guard !spaces.isEmpty, selectedSpace != nil else { throw NativeBrowserStateError.invalidState }
        let spaceIDs = spaces.map(\.id)
        let tabIDs = spaces.flatMap { $0.tabs.map(\.id) }
        guard Set(spaceIDs).count == spaceIDs.count, Set(tabIDs).count == tabIDs.count,
            Set(pendingDataStoreDeletions).count == pendingDataStoreDeletions.count,
            Set(spaceIDs).isDisjoint(with: pendingDataStoreDeletions)
        else { throw NativeBrowserStateError.invalidState }
        for space in spaces {
            guard !space.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                space.name.count <= 128, !space.tabs.isEmpty, space.selectedTab != nil
            else { throw NativeBrowserStateError.invalidState }
            for tab in space.tabs {
                guard tab.title.count <= 1_024, let url = URL(string: tab.address),
                    NativeBrowserAddress.mayLoadAsMainDocument(url)
                else { throw NativeBrowserStateError.invalidState }
            }
        }
    }

    @discardableResult
    mutating func createSpace(name: String) -> UUID {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
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
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
        if !trimmed.isEmpty { spaces[index].name = trimmed }
    }

    mutating func reorderSpaces(fromOffsets offsets: IndexSet, toOffset destination: Int) throws {
        guard !offsets.isEmpty else { return }
        guard offsets.allSatisfy({ spaces.indices.contains($0) }), (0...spaces.count).contains(destination) else {
            throw NativeBrowserStateError.invalidState
        }
        let moved = offsets.map { spaces[$0] }
        for index in offsets.reversed() { spaces.remove(at: index) }
        spaces.insert(contentsOf: moved, at: destination - offsets.filter { $0 < destination }.count)
    }

    mutating func deleteSpace(_ id: UUID) throws {
        guard spaces.count > 1 else { throw NativeBrowserStateError.lastSpace }
        guard let index = spaces.firstIndex(where: { $0.id == id }) else {
            throw NativeBrowserStateError.missingSpace
        }
        spaces.remove(at: index)
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

    mutating func reorderTabs(in spaceID: UUID, fromOffsets offsets: IndexSet, toOffset destination: Int) throws {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else {
            throw NativeBrowserStateError.missingSpace
        }
        guard !offsets.isEmpty else { return }
        guard offsets.allSatisfy({ spaces[index].tabs.indices.contains($0) }),
            (0...spaces[index].tabs.count).contains(destination)
        else { throw NativeBrowserStateError.invalidState }
        let moved = offsets.map { spaces[index].tabs[$0] }
        for position in offsets.reversed() { spaces[index].tabs.remove(at: position) }
        spaces[index].tabs.insert(contentsOf: moved, at: destination - offsets.filter { $0 < destination }.count)
    }

    /// The tab keeps its ID, live WebKit view and shared regular-store ownership.
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
        guard spaces[index].tabs.contains(where: { $0.id == id }) else { throw NativeBrowserStateError.missingTab }
        spaces[index].selectedTabID = id
    }

    mutating func closeTab(_ id: UUID, in spaceID: UUID) throws {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else {
            throw NativeBrowserStateError.missingSpace
        }
        guard let position = spaces[index].tabs.firstIndex(where: { $0.id == id }) else {
            throw NativeBrowserStateError.missingTab
        }
        spaces[index].tabs.remove(at: position)
        if spaces[index].tabs.isEmpty { spaces[index].tabs.append(.blank()) }
        if spaces[index].selectedTabID == id { spaces[index].selectedTabID = spaces[index].tabs[0].id }
    }

    mutating func recordNavigation(_ id: UUID, address: String, title: String) throws {
        guard let url = URL(string: address), NativeBrowserAddress.mayLoadAsMainDocument(url) else {
            throw NativeBrowserStateError.invalidState
        }
        guard let group = spaces.firstIndex(where: { $0.tabs.contains(where: { $0.id == id }) }),
            let tab = spaces[group].tabs.firstIndex(where: { $0.id == id })
        else { throw NativeBrowserStateError.missingTab }
        spaces[group].tabs[tab].address = address
        spaces[group].tabs[tab].title = String((title.isEmpty ? address : title).prefix(1_024))
    }

    mutating func finishDataStoreDeletion(_ id: UUID) {
        pendingDataStoreDeletions.removeAll { $0 == id }
    }
}
