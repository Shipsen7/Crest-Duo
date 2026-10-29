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
        #if os(iOS)
            // A preview's tab URLs can contain confidential search and account details.
            // Protect its directory and exclude the local session from device backups;
            // CloudKit must use its own explicitly reviewed sync format later.
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
            var excludedDirectory = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try excludedDirectory.setResourceValues(values)
        #endif
        let stateFile = directory.appendingPathComponent("browser-state.json", isDirectory: false)
        #if os(iOS)
            // Protect an existing preview session before reading it as well.
            if fileManager.fileExists(atPath: stateFile.path) {
                try fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.complete], ofItemAtPath: stateFile.path)
            }
        #endif
        fileURL = stateFile
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
        #if os(iOS)
            // Apply Data Protection to the temporary file before the atomic replace.
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        #else
            try data.write(to: fileURL, options: .atomic)
        #endif
    }
}
