import UIKit
import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserPageConfigurationTests: XCTestCase {
    // MARK: - Actions - Configuration

    func testContextPreviewKeepsTheSourceProfileWithoutChangingItsPreferencesOrPage() throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let source = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        let url = try XCTUnwrap(URL(string: "https://preview.crest.test"))
        let preview = MobileBrowserLinkPreviewController(url: url, source: source, isCurrent: { true })

        XCTAssertTrue(preview.webView.configuration.websiteDataStore === source.configuration.websiteDataStore)
        XCTAssertFalse(preview.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(
            preview.webView.configuration.userContentController === source.configuration.userContentController)
        XCTAssertFalse(preview.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        XCTAssertTrue(source.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        XCTAssertNil(source.url)
    }

    // MARK: - Actions - Input

    func testResizingKeepsFocusedInputVisibleWithoutChangingItsValueOrSelection() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        MobileWebKit.decorate(configuration)
        let webView = MobileWebKit.makeWebView(configuration: configuration)
        let controller = UIViewController()
        controller.view = webView
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 700, height: 1000))
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        webView.loadSimulatedRequest(
            URLRequest(url: try XCTUnwrap(URL(string: "https://input.crest.test/"))),
            responseHTML: """
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>body{margin:0;padding-top:500px;padding-bottom:1000px}input{font-size:20px}</style>
                <input id="editor" value="Retained-123">
                """
        )
        try await waitUntil { !webView.isLoading && webView.url != nil }
        _ = try await webView.evaluateJavaScript(
            "const editor = document.getElementById('editor'); editor.focus(); editor.setSelectionRange(3, 7); true"
        )
        for size in [
            CGSize(width: 1000, height: 300), CGSize(width: 700, height: 1000),
            CGSize(width: 1000, height: 300), CGSize(width: 700, height: 1000),
        ] {
            window.frame.size = size
            window.layoutIfNeeded()
            try await waitUntil {
                try await webView.evaluateJavaScript(
                    """
                    (() => {
                      const editor = document.getElementById('editor');
                      const rect = editor.getBoundingClientRect();
                      const viewport = window.visualViewport;
                      return document.activeElement === editor && editor.value === 'Retained-123'
                        && editor.selectionStart === 3 && editor.selectionEnd === 7
                        && rect.top >= viewport.offsetTop
                        && Math.floor(rect.bottom) <= Math.ceil(viewport.offsetTop + viewport.height);
                    })()
                    """
                ) as? Bool == true
            }
        }
    }

    private func waitUntil(_ condition: @escaping @MainActor () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while try await !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("The focused editor did not remain visible with its input state intact.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}
