import SwiftUI
import UIKit

/// A window-level cover also covers this app's presented sheets, unlike a
/// SwiftUI overlay on the underlying browser view. Device capture timing still
/// needs acceptance testing; this cannot prevent screenshots while active.
struct NativePrivacyCover: UIViewRepresentable {
    func makeUIView(context: Context) -> CoverAnchor { CoverAnchor() }
    func updateUIView(_ uiView: CoverAnchor, context: Context) {}

    @MainActor
    final class CoverAnchor: UIView {
        private var cover: UIView?

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            NotificationCenter.default.addObserver(
                self, selector: #selector(showCover),
                name: UIApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(
                self, selector: #selector(hideCover),
                name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        required init?(coder: NSCoder) { nil }
        deinit { NotificationCenter.default.removeObserver(self) }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if UIApplication.shared.applicationState != .active { showCover() }
        }

        override func willMove(toWindow newWindow: UIWindow?) {
            if newWindow !== window { hideCover() }
            super.willMove(toWindow: newWindow)
        }

        @objc private func showCover() {
            guard let window else { return }
            if let cover {
                window.bringSubviewToFront(cover)
                return
            }
            let shield = UIView(frame: window.bounds)
            shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            shield.backgroundColor = .systemBackground
            shield.accessibilityViewIsModal = true
            window.addSubview(shield)
            cover = shield
        }
        @objc private func hideCover() {
            cover?.removeFromSuperview()
            cover = nil
        }
    }
}
