import Foundation
import WebKit

struct NativeCompletedDownload: Identifiable {
    let id: UUID
    let name: String
    let fileURL: URL
    let isPrivate: Bool
}

/// WebKit owns transfers and credentials. Files stay in protected temporary
/// storage until the user explicitly exports a copy through the Files picker.
@MainActor
final class NativeDownloadCenter: NSObject, WKDownloadDelegate {
    weak var owner: NativeBrowserSession?

    private struct Transfer {
        let id: UUID
        let download: WKDownload
        let isPrivate: Bool
        let isGenerated: Bool
        var name: String?
        var destination: URL?
    }

    private let directory: URL
    private var transfers: [ObjectIdentifier: Transfer] = [:]
    var activeCount: Int { transfers.count }

    init(
        directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FennavioNativeDownloads", isDirectory: true)
    ) throws {
        self.directory = directory
        super.init()
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
    }

    func begin(_ download: WKDownload, isPrivate: Bool) {
        let original = download.originalRequest?.url
        let secureRequest = original.map(NativeBrowserAddress.isHTTPS) == true
        let generated =
            download.originatingFrame.securityOrigin.protocol == "https"
            && (original == nil || original?.scheme?.lowercased() == "blob")
        guard download.isUserInitiated, secureRequest || generated, transfers.count < 4 else {
            download.cancel(nil)
            owner?.downloadDidFail("An unrequested, insecure or excess download was blocked.", isPrivate: isPrivate)
            return
        }
        transfers[ObjectIdentifier(download)] = Transfer(
            id: UUID(), download: download, isPrivate: isPrivate, isGenerated: generated)
        download.delegate = self
    }

    func cancelPrivate() {
        let privateTasks = transfers.filter { $0.value.isPrivate }
        for (key, task) in privateTasks {
            transfers.removeValue(forKey: key)
            cancel(task)
        }
    }

    func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        let key = ObjectIdentifier(download)
        guard var task = transfers[key] else { return nil }
        let secureResponse = response.url.map(NativeBrowserAddress.isHTTPS) == true
        let generatedResponse =
            task.isGenerated && (response.url == nil || response.url?.scheme?.lowercased() == "blob")
        guard secureResponse || generatedResponse else {
            transfers.removeValue(forKey: key)
            cancel(task)
            owner?.downloadDidFail("An insecure download response was blocked.", isPrivate: task.isPrivate)
            return nil
        }
        let folder = directory.appendingPathComponent(task.id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            #if os(iOS)
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete], ofItemAtPath: folder.path)
            #endif
            let name = NativeDownloadFilename(suggested: suggestedFilename).value
            let destination = folder.appendingPathComponent(name, isDirectory: false)
            task.name = name
            task.destination = destination
            transfers[key] = task
            return destination
        } catch {
            transfers.removeValue(forKey: key)
            cancel(task)
            owner?.downloadDidFail("Could not prepare a protected download location.", isPrivate: task.isPrivate)
            return nil
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let task = transfers.removeValue(forKey: ObjectIdentifier(download)) else { return }
        download.delegate = nil
        guard let destination = task.destination, let name = task.name else {
            removeFiles(for: task.id)
            return
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw NativeBrowserStateError.invalidState
            }
            #if os(iOS)
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
            #endif
            owner?.downloadDidFinish(
                NativeCompletedDownload(id: task.id, name: name, fileURL: destination, isPrivate: task.isPrivate))
        } catch {
            removeFiles(for: task.id)
            owner?.downloadDidFail("Could not protect the downloaded file.", isPrivate: task.isPrivate)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        guard let task = transfers.removeValue(forKey: ObjectIdentifier(download)) else { return }
        download.delegate = nil
        removeFiles(for: task.id)
        // Resume data and arbitrary error descriptions can contain credentials/URLs.
        owner?.downloadDidFail("The download failed. Try again from the website.", isPrivate: task.isPrivate)
    }

    func download(
        _ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        decisionHandler: @escaping @MainActor @Sendable (WKDownload.RedirectPolicy) -> Void
    ) {
        let key = ObjectIdentifier(download)
        guard let task = transfers[key] else {
            decisionHandler(.cancel)
            return
        }
        guard let url = request.url, NativeBrowserAddress.isHTTPS(url) else {
            transfers.removeValue(forKey: key)
            decisionHandler(.cancel)
            cancel(task)
            owner?.downloadDidFail("An insecure download redirect was blocked.", isPrivate: task.isPrivate)
            return
        }
        decisionHandler(.allow)
    }

    func download(
        _ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }

    private func cancel(_ task: Transfer) {
        task.download.delegate = nil
        let folder = directory.appendingPathComponent(task.id.uuidString, isDirectory: true)
        // Wait until WebKit stops writing before removing a partial private file.
        task.download.cancel { _ in try? FileManager.default.removeItem(at: folder) }
    }

    private func removeFiles(for id: UUID) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString, isDirectory: true))
    }
}
