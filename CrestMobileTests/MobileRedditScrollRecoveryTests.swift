import UIKit
import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileRedditScrollRecoveryTests: XCTestCase {
    // MARK: - Variables

    private var window: UIWindow?

    // MARK: - Actions - Compatibility

    func testHiddenConsentReleasesScrollingWithoutChoosingConsent() async throws {
        let page = try await fixture(
            body: """
                <dialog id="data-protection-consent-dialog" style="display:none">
                  <button onclick="document.body.dataset.accepted='yes'">Accept</button>
                </dialog>
                <script>document.querySelector('dialog').showModal()</script>
                """
        )
        try await waitUntil(page, expression: "getComputedStyle(document.body).overflowY === 'auto'")
        let closed = try await page.evaluateJavaScript("!document.querySelector('dialog').open") as? Bool
        let untouched = try await page.evaluateJavaScript("!document.body.dataset.accepted") as? Bool
        XCTAssertEqual(closed, true)
        XCTAssertEqual(untouched, true)
    }

    func testVisibleConsentAndSignInKeepTheirScrollLocks() async throws {
        let page = try await fixture(body: "<dialog id='data-protection-consent-dialog' open>Consent</dialog>")
        try await waitForRecoveryTurn(page)
        let consentLocked = try await page.evaluateJavaScript("getComputedStyle(document.body).overflowY") as? String
        XCTAssertEqual(consentLocked, "hidden")
        _ = try await page.evaluateJavaScript(
            """
            document.querySelector('dialog').style.display = 'none';
            document.body.insertAdjacentHTML('beforeend', '<dialog open>Sign in</dialog>'); true
            """
        )
        try await waitForRecoveryTurn(page)
        let loginLocked = try await page.evaluateJavaScript("getComputedStyle(document.body).overflowY") as? String
        XCTAssertEqual(loginLocked, "hidden")
    }

    func testLateConsentAndLaterModalRestoreTheOriginalOverflow() async throws {
        let page = try await fixture(body: "<main>Article</main>")
        _ = try await page.evaluateJavaScript(
            """
            document.body.insertAdjacentHTML('beforeend',
              '<shreddit-cookie-banner style="display:none"></shreddit-cookie-banner>'); true
            """
        )
        try await waitUntil(page, expression: "getComputedStyle(document.body).overflowY === 'auto'")
        _ = try await page.evaluateJavaScript(
            "document.body.insertAdjacentHTML('beforeend', '<dialog open>Sign in</dialog>'); true"
        )
        try await waitUntil(page, expression: "getComputedStyle(document.body).overflowY === 'hidden'")
        let original =
            try await page.evaluateJavaScript("document.body.style.getPropertyValue('overflow-y')") as? String
        XCTAssertEqual(original, "")
        _ = try await page.evaluateJavaScript("document.querySelector('dialog').remove(); true")
        try await waitUntil(page, expression: "getComputedStyle(document.body).overflowY === 'auto'")
    }

    func testRecoveryDoesNotChangeOtherOrigins() async throws {
        for origin in ["https://notreddit.com", "https://reddit.com.example.test", "http://www.reddit.com"] {
            let page = try await fixture(
                origin: origin, body: "<shreddit-cookie-banner style='display:none'></shreddit-cookie-banner>"
            )
            try await waitForRecoveryTurn(page)
            let overflow = try await page.evaluateJavaScript("getComputedStyle(document.body).overflowY") as? String
            XCTAssertEqual(overflow, "hidden", origin)
        }
    }

    // MARK: - Actions - Fixtures

    private func fixture(origin: String = "https://www.reddit.com", body: String) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        MobileWebKit.decorate(configuration)
        let page = MobileWebKit.makeWebView(configuration: configuration)
        let controller = UIViewController()
        controller.view = page
        window?.isHidden = true
        let fixtureWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        fixtureWindow.rootViewController = controller
        fixtureWindow.isHidden = false
        window = fixtureWindow
        addTeardownBlock { @MainActor in
            fixtureWindow.isHidden = true
            fixtureWindow.rootViewController = nil
        }
        page.loadSimulatedRequest(
            URLRequest(url: try XCTUnwrap(URL(string: origin + "/fixture"))),
            responseHTML: """
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <style>body { overflow: hidden !important; } main { height: 3000px; }</style>
                <body>\(body)<main>Content</main></body>
                """
        )
        try await waitUntil(page, expression: "document.readyState === 'complete'")
        return page
    }

    private func waitForRecoveryTurn(_ page: WKWebView) async throws {
        _ = try await page.callAsyncJavaScript(
            "await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))); return true;",
            arguments: [:], in: nil, contentWorld: .page
        )
    }

    private func waitUntil(_ page: WKWebView, expression: String) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while true {
            if !page.isLoading, page.url != nil,
                try await page.evaluateJavaScript(expression) as? Bool == true
            {
                return
            }
            guard ContinuousClock.now < deadline else {
                XCTFail("Reddit compatibility fixture did not reach its expected input state: \(expression)")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}
