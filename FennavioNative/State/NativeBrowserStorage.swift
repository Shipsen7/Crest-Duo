import Foundation

/// Kept in the new preview app's own sandbox, never in the installed
/// Fennavio/Crest persistence directory or CloudKit container.
struct NativeBrowserStorage {
    let fileURL: URL

    init(fileManager: FileManager = .default) throws {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = support.appendingPathComponent("FennavioNative", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("browser-state.json", isDirectory: false)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() throws -> NativeBrowserState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return NativeBrowserState() }
        let data = try Data(contentsOf: fileURL)
        let state = try JSONDecoder().decode(NativeBrowserState.self, from: data)
        try state.validate()
        return state
    }

    func save(_ state: NativeBrowserState) throws {
        try state.validate()
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}
