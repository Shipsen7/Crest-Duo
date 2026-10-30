import Foundation

/// A single visible path component, bounded in bytes rather than characters.
struct NativeDownloadFilename {
    let value: String

    init(suggested: String) {
        let basename = (suggested as NSString).lastPathComponent
        var safe = ""
        for character in basename {
            let unsafe =
                character == "/" || character == "\\" || character == ":"
                || character.unicodeScalars.contains {
                    CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format
                }
            let next = unsafe ? "_" : String(character)
            guard safe.utf8.count + next.utf8.count <= 180 else { break }
            safe += next
        }
        let trimmed = safe.trimmingCharacters(in: .whitespacesAndNewlines)
        value = trimmed.isEmpty || trimmed.allSatisfy({ $0 == "." }) ? "Download" : trimmed
    }
}
