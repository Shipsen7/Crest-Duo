import SwiftUI
import WebKit

/// Moves the tab's retained native view between presentation hosts without
/// reconstructing its document, form inputs, or back-forward history.
struct NativeWebPage: UIViewRepresentable {
    let session: NativeBrowserSession
    let tabID: UUID

    func makeUIView(context: Context) -> UIView {
        let host = UIView(frame: .zero)
        host.backgroundColor = .systemBackground
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        guard let page = session.webView(for: tabID), page.superview !== host else { return }
        page.removeFromSuperview()
        page.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(page)
        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: host.topAnchor),
            page.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            page.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
    }
}
