import Foundation
import Observation
import WebKit

/// Applies the bundled Dark Reader API in WebKit's isolated client world.
/// Changing appearance never reloads the document or touches its form values.
@MainActor
@Observable
final class MobileWebPageDarkMode {
    // MARK: - Static Variables

    private static let library: String? = Bundle.main.url(forResource: "DarkReader", withExtension: "js").flatMap {
        try? String(contentsOf: $0, encoding: .utf8)
    }
    private static let startupScripts = NSMapTable<WKUserContentController, WKUserScript>.weakToStrongObjects()

    // MARK: - Variables

    private let webView: WKWebView
    private let preferences: MobileWebsiteDarkModePreferences
    private let profileID: UUID
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    private(set) var failed = false
    private var documentURL: URL?

    var canToggle: Bool { Self.library != nil && origin != nil }
    var isEnabled: Bool {
        origin.map { preferences.isEnabled(for: $0, in: profileID) } ?? false
    }

    private var origin: SiteOrigin? {
        documentURL.flatMap(SiteOrigin.init(url:))
    }

    // MARK: - Initializers

    init(
        webView: WKWebView, preferences: MobileWebsiteDarkModePreferences, profileID: UUID
    ) {
        self.webView = webView
        self.preferences = preferences
        self.profileID = profileID
        preferences.register(self)
    }

    // MARK: - Actions - Appearance

    func setEnabled(_ enabled: Bool) {
        guard canToggle, let origin else { return }
        preferences.setEnabled(enabled, for: origin, in: profileID)
    }

    func preferencesDidChange() {
        installStartupScript()
        applyToDocument()
    }

    func applyToDocument() {
        applyTask?.cancel()
        documentURL = webView.url
        failed = false
        guard let origin else { return }
        let enabled = isEnabled
        let expectedOrigin = origin.displayName
        let library = enabled ? Self.library ?? "" : ""
        let script = Self.script(library: library)
        applyTask = Task { [weak self] in
            guard !Task.isCancelled, let self else { return }
            do {
                let result = try await webView.callAsyncJavaScript(
                    """
                    if (location.origin !== expectedOrigin) return false;
                    if (!enabled) { globalThis.DarkReader?.disable(); return true; }
                    \(script)
                    return globalThis.DarkReader?.isEnabled() === true;
                    """,
                    arguments: ["expectedOrigin": expectedOrigin, "enabled": enabled],
                    in: nil, contentWorld: .defaultClient
                ) as? Bool
                guard !Task.isCancelled, self.origin?.displayName == expectedOrigin else { return }
                failed = result != true
            } catch {
                guard !Task.isCancelled, self.origin?.displayName == expectedOrigin else { return }
                failed = true
            }
        }
    }

    // MARK: - Actions - Navigation

    private func installStartupScript() {
        let controller = webView.configuration.userContentController
        if let startupScript = Self.startupScripts.object(forKey: controller) {
            let retained = controller.userScripts.filter { $0 !== startupScript }
            controller.removeAllUserScripts()
            for script in retained { controller.addUserScript(script) }
            Self.startupScripts.removeObject(forKey: controller)
        }
        let origins = preferences.enabledOrigins(in: profileID)
        guard !origins.isEmpty, let library = Self.library,
            let data = try? JSONEncoder().encode(origins), let encodedOrigins = String(data: data, encoding: .utf8)
        else { return }
        let script = WKUserScript(
            source: """
                (() => {
                  if (!\(encodedOrigins).includes(location.origin)) return;
                  \(Self.script(library: library))
                })();
                """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .defaultClient
        )
        controller.addUserScript(script)
        Self.startupScripts.setObject(script, forKey: controller)
    }

    private static func script(library: String) -> String {
        """
        if (!globalThis.DarkReader) {
          \(library)
          // Read only ordinary site assets through WebKit's CORS boundary.
          // No native fetch bridge or Dark Reader update service is installed.
          globalThis.DarkReader.setFetchMethod(url => fetch(url, {
            credentials: 'omit', referrerPolicy: 'no-referrer', mode: 'cors', redirect: 'error'
          }));
        }
        globalThis.DarkReader.enable({
          brightness: 100, contrast: 100, sepia: 0,
          darkSchemeBackgroundColor: '#181a1b', darkSchemeTextColor: '#e8e6e3'
        }, { disableStyleSheetsProxy: true, ignoreImageAnalysis: ['*'],
          invert: [], css: '', ignoreInlineStyle: [] });
        """
    }
}
