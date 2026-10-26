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

    func testMovingAFocusedPageBetweenHostsPreservesSelectionAndTyping() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        MobileWebKit.decorate(configuration)
        let webView = MobileWebKit.makeWebView(configuration: configuration)
        let controller = UIViewController()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 700, height: 1000)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        let original = MobileBrowserWebHostView(frame: window.bounds)
        controller.view.addSubview(original)
        original.attach(webView)
        webView.loadSimulatedRequest(
            URLRequest(url: try XCTUnwrap(URL(string: "https://input.crest.test/"))),
            responseHTML: """
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <input id="editor" value="Retained-123"><textarea id="multiline">Retained-123</textarea>
                <div id="rich" contenteditable="true">Retained-123</div>
                """
        )
        try await waitUntil { !webView.isLoading && webView.url != nil }
        var previous = original
        for editorID in ["editor", "multiline", "rich"] {
            _ = try await webView.evaluateJavaScript(
                """
                (() => {
                  const editor = document.getElementById('\(editorID)');
                  editor.focus();
                  if (editor.isContentEditable) {
                    const selection = getSelection();
                    selection.setBaseAndExtent(editor.firstChild, 3, editor.firstChild, 7);
                  } else editor.setSelectionRange(3, 7);
                })(); true
                """
            )
            webView.becomeFirstResponder()
            try await waitUntil { self.nativeResponder(in: webView) != nil }
            let responder = try XCTUnwrap(nativeResponder(in: webView))
            XCTAssertTrue(responder is any UITextInput)
            for removesFirst in [false, true] {
                let replacement = MobileBrowserWebHostView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
                if removesFirst {
                    // The system can hide the keyboard before the root gets
                    // its new width, while the DOM editor remains focused.
                    (webView as? MobileWebView)?.rememberKeyboardFocus()
                    (webView as? MobileWebView)?.keyboardWillHide()
                    responder.resignFirstResponder()
                    (webView as? MobileWebView)?.prepareForLayoutTransition()
                    previous.removeFromSuperview()
                    previous.detach(stopsLoading: false)
                }
                // SwiftUI builds the new host before putting it in the window.
                replacement.attach(webView)
                controller.view.addSubview(replacement)
                if !removesFirst {
                    previous.detach(stopsLoading: false)
                    previous.removeFromSuperview()
                }
                replacement.layoutIfNeeded()
                previous = replacement
                try await waitUntil { responder.isFirstResponder }
                XCTAssertTrue(responder.isFirstResponder, "\(editorID), removes first: \(removesFirst)")
                let state =
                    try await webView.evaluateJavaScript(
                        """
                        (() => {
                          const editor = document.getElementById('\(editorID)');
                          const selection = getSelection();
                          return document.activeElement === editor && (editor.isContentEditable
                            ? selection.anchorOffset === 3 && selection.focusOffset === 7
                            : editor.selectionStart === 3 && editor.selectionEnd === 7);
                        })()
                        """
                    ) as? Bool
                XCTAssertEqual(state, true, "\(editorID), removes old host first: \(removesFirst)")
            }
            _ = try await webView.evaluateJavaScript("document.execCommand('insertText', false, 'X'); true")
            let value =
                try await webView.evaluateJavaScript(
                    "document.getElementById('\(editorID)').value ?? document.getElementById('\(editorID)').textContent"
                ) as? String
            XCTAssertEqual(value, "RetXd-123")
        }

        let modal = UIViewController()
        modal.modalPresentationStyle = .fullScreen
        let modalHost = MobileBrowserWebHostView(frame: window.bounds)
        modal.view.addSubview(modalHost)
        (webView as? MobileWebView)?.prepareForLayoutTransition()
        modalHost.attach(webView)
        await withCheckedContinuation { continuation in
            controller.present(modal, animated: true) { continuation.resume() }
        }
        try await waitUntil { self.nativeResponder(in: webView) != nil }
        XCTAssertNotNil(nativeResponder(in: webView), "The compact page must resume input after presentation.")
        (webView as? MobileWebView)?.prepareForLayoutTransition()
        await withCheckedContinuation { continuation in
            modal.dismiss(animated: true) { continuation.resume() }
        }
        modalHost.detach(stopsLoading: false)
        try await waitUntil { self.nativeResponder(in: webView) != nil }
        XCTAssertNotNil(nativeResponder(in: webView), "The expanded page must resume input after dismissal.")

        // Putting a tab away must not reopen its keyboard on a later visit.
        previous.removeFromSuperview()
        previous.detach(stopsLoading: false)
        try await Task.sleep(for: .milliseconds(50))
        let returning = MobileBrowserWebHostView(frame: window.bounds)
        returning.attach(webView)
        controller.view.addSubview(returning)
        XCTAssertNil(nativeResponder(in: webView))

        // A native address editor that took focus owns it, even if the same
        // web page is moved again in the current layout turn.
        _ = try await webView.evaluateJavaScript("document.getElementById('editor').focus(); true")
        webView.becomeFirstResponder()
        returning.removeFromSuperview()
        let address = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        controller.view.addSubview(address)
        XCTAssertTrue(address.becomeFirstResponder())
        controller.view.addSubview(returning)
        XCTAssertTrue(address.isFirstResponder)
        XCTAssertNil(nativeResponder(in: webView))
    }

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
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while try await !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail("The focused editor did not remain visible with its input state intact.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func nativeResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for child in view.subviews {
            if let responder = nativeResponder(in: child) { return responder }
        }
        return nil
    }
}
