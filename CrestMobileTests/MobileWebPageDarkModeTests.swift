import UIKit
import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileWebPageDarkModeTests: XCTestCase {
    // MARK: - Actions - Input preservation

    func testSwitchingPreservesTheDocumentAndItsEditor() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let preferences = MobileWebsiteDarkModePreferences()
        let appearance = MobileWebPageDarkMode(webView: webView, preferences: preferences, profileID: UUID())
        let controller = UIViewController()
        controller.view = webView
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let url = try XCTUnwrap(URL(string: "https://appearance.crest.test/editor"))
        webView.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: """
                <style>body { background: white; color: black }</style>
                <input id="editor" value="Retained-123">
                """
        )
        try await waitUntil { !webView.isLoading && webView.url == url }
        appearance.applyToDocument()
        _ = try await webView.evaluateJavaScript(
            "const editor = document.querySelector('input'); editor.focus(); editor.setSelectionRange(3, 7); true"
        )
        for enabled in [true, false] {
            appearance.setEnabled(enabled)
            try await waitUntil {
                try await webView.callAsyncJavaScript(
                    "return (globalThis.DarkReader?.isEnabled() === true) === enabled;",
                    arguments: ["enabled": enabled], in: nil, contentWorld: .defaultClient
                ) as? Bool == true
            }
            let retained =
                try await webView.evaluateJavaScript(
                    """
                    editor.value === 'Retained-123' && editor.selectionStart === 3 && editor.selectionEnd === 7
                      && document.activeElement === editor
                    """
                ) as? Bool
            XCTAssertEqual(retained, true)
            XCTAssertEqual(webView.url, url)
            XCTAssertFalse(webView.canGoBack)
        }
    }

    // MARK: - Actions - Script ownership

    func testSharedPopupControllerKeepsOneAppearanceScriptAndPreservesOtherScripts() throws {
        let preferences = MobileWebsiteDarkModePreferences()
        let profile = UUID()
        let origin = try XCTUnwrap(URL(string: "https://appearance.crest.test").flatMap(SiteOrigin.init(url:)))
        preferences.setEnabled(true, for: origin, in: profile)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let unrelated = WKUserScript(
            source: "globalThis.retainedExtension = true;", injectionTime: .atDocumentEnd, forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(unrelated)
        let first = MobileWebPageDarkMode(
            webView: WKWebView(frame: .zero, configuration: configuration), preferences: preferences, profileID: profile
        )
        let popup = MobileWebPageDarkMode(
            webView: WKWebView(frame: .zero, configuration: configuration), preferences: preferences, profileID: profile
        )
        XCTAssertEqual(configuration.userContentController.userScripts.count, 2)
        preferences.setEnabled(false, for: origin, in: profile)
        XCTAssertEqual(configuration.userContentController.userScripts.count, 1)
        XCTAssertTrue(configuration.userContentController.userScripts.first === unrelated)
        withExtendedLifetime((first, popup)) {}
    }

    // MARK: - Actions - Waiting

    private func waitUntil(_ condition: @escaping @MainActor () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while try await !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Website appearance did not reach its expected input state.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}
