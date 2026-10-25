import UIKit
import WebKit

/// The mobile WebKit behavior installed as a page is built: recommended
/// presentation, inline media, visible form input and the web view.
@MainActor
enum MobileWebKit {
    // MARK: - Static Variables

    static let preferredContentMode = WKWebpagePreferences.ContentMode.recommended

    /// A viewport resize can finish after WebKit's initial focus scroll, as
    /// the keyboard and the browser's page frame settle during rotation.
    /// Each frame scrolls its own focused editor; no input data leaves WebKit.
    static let focusedInputScript = WKUserScript(
        source: """
            (() => {
              let scheduled = false;
              let followsViewport = false;
              const revealEditor = () => {
                scheduled = false;
                let editor = document.activeElement;
                while (editor?.shadowRoot?.activeElement) editor = editor.shadowRoot.activeElement;
                if (!(editor instanceof HTMLElement)) return;
                if (!editor.matches('input, textarea') && !editor.isContentEditable) return;
                editor.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' });
              };
              const schedule = () => {
                if (scheduled) return;
                scheduled = true;
                requestAnimationFrame(revealEditor);
              };
              const viewportChanged = () => {
                followsViewport = true;
                schedule();
              };
              const viewportScrolled = () => {
                if (followsViewport) schedule();
              };
              const stopFollowing = () => { followsViewport = false; };
              window.addEventListener('resize', viewportChanged, { passive: true });
              window.visualViewport?.addEventListener('resize', viewportChanged, { passive: true });
              window.addEventListener('scroll', viewportScrolled, { passive: true });
              window.visualViewport?.addEventListener('scroll', viewportScrolled, { passive: true });
              document.addEventListener('focusin', viewportChanged, { passive: true });
              for (const event of ['pointerdown', 'touchstart', 'wheel']) {
                document.addEventListener(event, stopFollowing, { capture: true, passive: true });
              }
            })();
            """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false,
        in: .defaultClient
    )

    /// Keeps every video, including ones a page adds later, playing inline
    /// rather than taking over the screen.
    static let inlineVideoScript = WKUserScript(
        source: """
            (() => {
              const keepInline = (root) => {
                if (root instanceof HTMLVideoElement) {
                  root.setAttribute('playsinline', '');
                  root.setAttribute('webkit-playsinline', '');
                }
                root.querySelectorAll?.('video').forEach((video) => {
                  video.setAttribute('playsinline', '');
                  video.setAttribute('webkit-playsinline', '');
                });
              };

              keepInline(document);
              new MutationObserver((records) => {
                records.forEach((record) => {
                  record.addedNodes.forEach((node) => {
                    if (node instanceof Element) keepInline(node);
                  });
                });
              }).observe(document.documentElement, { childList: true, subtree: true });
            })();
            """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    // MARK: - Actions - Pages

    /// Adds mobile media and input behavior to a new page's configuration, on top of
    /// the settings both platforms share: the inactive scheduling policy above
    /// all, which lets WebKit suspend a resident background tab on the
    /// platform that jetsams.
    static func decorate(_ configuration: WKWebViewConfiguration) {
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.userContentController.addUserScript(inlineVideoScript)
        configuration.userContentController.addUserScript(focusedInputScript)
    }

    /// The web view over `configuration`, one the binding assembled or one
    /// WebKit made for a popup.
    static func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .clear
        return webView
    }
}
