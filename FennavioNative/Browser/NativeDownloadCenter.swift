import Foundation
import WebKit

/// Completed files remain inside the preview's protected temporary directory
/// until the person exports them through the system Files picker.
struct NativeCompletedDownload: Identifiable {
    let id: UUID
    let name: String
    let fileURL: URL
    let isPrivate: Bool
}

/// WebKit owns the network transfer and credentials. This delegate only gives
/// downloads a sandbox destination and never loads URLs itself.
@MainActor
final class NativeDownloadCenter: NSObject, WKDownloadDelegate {
    weak var owner: NativeBrowserSession?

    private struct Transfer {
        let id: UUID
        let download: WKDownload
        let isPrivate: Bool
        var name: String?
        var destination: URL?
    }

    private let directory: URL
    private var transfers: [ObjectIdentifier: Transfer] = [:]

    override init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FennavioNativeDownloads", isDirectory: true)
        super.init()
        // Only this app's sandbox directory is touched. A terminated preview
        // leaves no recoverable download history or leftover bank statements.
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
    }

    func begin(_ download: WKDownload, isPrivate: Bool) {
        let task = Transfer(id: UUID(), download: download, isPrivate: isPrivate)
        transfers[ObjectIdentifier(download)] = task
        download.delegate = self
    }

    func cancelPrivate() {
        let privateTasks = transfers.filter { $0.value.isPrivate }
        for (key, task) in privateTasks {
            task.download.cancel(nil)
            removeFiles(for: task.id)
            transfers.removeValue(forKey: key)
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String)
        async -> URL?
    {
        let key = ObjectIdentifier(download)
        guard var task = transfers[key] else { return nil }
        let folder = directory.appendingPathComponent(task.id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            #if os(iOS)
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete], ofItemAtPath: folder.path)
            #endif
            let filename = Self.safeFilename(suggestedFilename)
            let destination = folder.appendingPathComponent(filename, isDirectory: false)
            task.name = filename
            task.destination = destination
            transfers[key] = task
            return destination
        } catch {
            owner?.downloadDidFail("Could not prepare a protected download location.")
            return nil
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let task = transfers.removeValue(forKey: ObjectIdentifier(download)),
            let destination = task.destination, let name = task.name
        else { return }
        #if os(iOS)
            do {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
            } catch {
                removeFiles(for: task.id)
                owner?.downloadDidFail("Could not protect the downloaded file.")
                return
            }
        #endif
        owner?.downloadDidFinish(
            NativeCompletedDownload(id: task.id, name: name, fileURL: destination, isPrivate: task.isPrivate))
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        guard let task = transfers.removeValue(forKey: ObjectIdentifier(download)) else { return }
        removeFiles(for: task.id)
        owner?.downloadDidFail(error.localizedDescription)
    }

    func download(
        _ download: WKDownload,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        decisionHandler: @escaping @MainActor @Sendable (WKDownload.RedirectPolicy) -> Void
    ) {
        guard transfers[ObjectIdentifier(download)] != nil,
            let url = request.url, NativeBrowserAddress.mayLoadAsMainDocument(url)
        else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private func removeFiles(for id: UUID) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    static func safeFilename(_ suggested: String) -> String {
        let basename = (suggested as NSString).lastPathComponent
        let safe = String(
            basename.map { character in
                let unsafe =
                    character == "/" || character == "\\" || character == ":"
                    || character.unicodeScalars.contains {
                        CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format
                    }
                return unsafe ? "_" : character
            })
        let limited = String(safe.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
        return limited.isEmpty || limited == "." || limited == ".." ? "Download" : limited
    }
}
