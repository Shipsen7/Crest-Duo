import Foundation

/// Local, bounded, atomic storage in this app's own sandbox. Invalid or locked
/// data is an error, never an instruction to reset or overwrite a session.
struct NativeBrowserStorage {
    static let maximumFileBytes = 16 * 1_024 * 1_024
    let fileURL: URL

    init(fileManager: FileManager = .default) throws {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        var directory = support.appendingPathComponent("FennavioNative", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        fileURL = directory.appendingPathComponent("browser-state.json", isDirectory: false)
    }

    init(fileURL: URL) { self.fileURL = fileURL }

    private var libraryURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("page-library.json") }

    func load() throws -> NativeBrowserState {
        guard let data = try read(fileURL) else { return NativeBrowserState() }
        let state = try JSONDecoder().decode(NativeBrowserState.self, from: data)
        try state.validate()
        return state
    }

    func save(_ state: NativeBrowserState) throws {
        try state.validate()
        try write(JSONEncoder().encode(state), to: fileURL)
    }

    func loadLibrary() throws -> NativePageLibrary {
        guard let data = try read(libraryURL) else { return NativePageLibrary() }
        let library = try JSONDecoder().decode(NativePageLibrary.self, from: data)
        try library.validate()
        return library
    }

    func saveLibrary(_ library: NativePageLibrary) throws {
        try library.validate()
        try write(JSONEncoder().encode(library), to: libraryURL)
    }

    private func read(_ url: URL) throws -> Data? {
        guard try isExistingRegularFile(url) else { return nil }
        #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumFileBytes + 1) ?? Data()
        guard data.count <= Self.maximumFileBytes else { throw NativeBrowserStateError.limitExceeded }
        return data
    }

    private func write(_ data: Data, to url: URL) throws {
        guard data.count <= Self.maximumFileBytes else { throw NativeBrowserStateError.limitExceeded }
        _ = try isExistingRegularFile(url)
        #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
            try data.write(to: url, options: .atomic)
        #endif
    }

    /// attributesOfItem inspects the link itself, including a dangling link.
    /// Only a genuinely absent file starts an empty session; other errors surface.
    private func isExistingRegularFile(_ url: URL) throws -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw NativeBrowserStateError.invalidState
            }
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return false
        }
    }
}
