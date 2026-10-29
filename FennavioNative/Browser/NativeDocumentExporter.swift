import SwiftUI
import UIKit

/// System-owned document export keeps downloaded bytes outside our UI code.
struct NativeDocumentExporter: UIViewControllerRepresentable {
    let fileURL: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}
