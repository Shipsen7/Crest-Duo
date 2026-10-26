import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserGeolocationBridgeTests: XCTestCase {
    func testDirectBridgeCannotBypassFramePolicyOrPageWorldSpoofing() async throws {
        let fixture = try makeFixture()
        defer { fixture.page.release(keepingState: false) }
        fixture.page.webView.loadSimulatedRequest(URLRequest(url: fixture.url), responseHTML: "<html>Frames</html>")
        try await waitUntil("the frame host") {
            fixture.page.webView.url == fixture.url && !fixture.page.webView.isLoading
        }
        // Exercise an iframe container policy independently of HTTP policy
        // header support in the installed WebKit engine.
        _ = try await fixture.page.webView.callAsyncJavaScript(
            """
            globalThis.frameReported = false;
            addEventListener('message', () => { globalThis.frameReported = true; }, { once: true });
            const frame = document.createElement('iframe');
            frame.allow = "geolocation 'none'";
            frame.srcdoc = `<script>
              Object.defineProperty(document, 'permissionsPolicy', { value: { allowsFeature: () => true } });
              navigator.permissions.query = async () => ({ state: 'granted' });
              webkit.messageHandlers.crestGeolocation.postMessage({
                version: 1, action: 'watchPosition', documentIdentifier: crypto.randomUUID(), identifier: 'direct'
              });
              parent.postMessage('requested', '*');
            </script>`;
            document.body.append(frame);
            """, arguments: [:], in: nil, contentWorld: .page)
        try await waitUntil("the restricted frame request") {
            try await fixture.page.webView.evaluateJavaScript("globalThis.frameReported === true") as? Bool == true
        }
        let nativeError = try await fixture.page.webView.callAsyncJavaScript(
            """
            return await new Promise(resolve => frames[0].navigator.geolocation.getCurrentPosition(
              () => resolve(0), error => resolve(error.code), { timeout: 0, maximumAge: 0 }));
            """, arguments: [:], in: nil, contentWorld: .world(name: "fennavio-test-policy"))
        XCTAssertEqual(nativeError as? Int, 1, "The fixture must be denied by WebKit's original API")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(fixture.service.watchRequests.isEmpty)
        XCTAssertTrue(fixture.service.currentRequests.isEmpty)
    }

    func testCrossOriginFrameNeedsDelegationAndRetainsAuthorizedLocation() async throws {
        let server = try BrowserPrivacyHTTPServer()
        try await server.start()
        defer { server.stop() }
        server.overrideResponse = { request in
            let html =
                request.path == "/child"
                ? """
                <script>
                webkit.messageHandlers.crestGeolocation.postMessage({
                  version: 1, action: 'watchPosition', documentIdentifier: crypto.randomUUID(), identifier: 'direct'
                });
                navigator.geolocation.getCurrentPosition(
                  () => parent.postMessage('position', '*'),
                  error => parent.postMessage(error.code === 1 ? 'denied' : 'error', '*'));
                parent.postMessage('requested', '*');
                </script>
                """ : "<html>Frame host</html>"
            return ("200 OK", "Content-Type: text/html\r\n", Data(html.utf8))
        }
        for allowsLocation in [false, true] {
            let fixture = try makeFixture(url: server.url(host: "localhost", path: "/host"))
            defer { fixture.page.release(keepingState: false) }
            let childURL = server.url(host: "127.0.0.1", path: "/child")
            fixture.page.permissionCenter.setDecision(
                .grantPersistently, for: .location, origin: try XCTUnwrap(SiteOrigin(url: childURL)),
                in: fixture.page.spaceID)
            fixture.page.webView.load(URLRequest(url: fixture.url))
            try await waitUntil("the cross-origin host") {
                fixture.page.webView.url == fixture.url && !fixture.page.webView.isLoading
            }
            _ = try await fixture.page.webView.callAsyncJavaScript(
                """
                globalThis.frameDenied = false;
                addEventListener('message', event => { if (event.data === 'denied') globalThis.frameDenied = true; });
                const frame = document.createElement('iframe');
                if (allowsLocation) frame.allow = 'geolocation';
                frame.src = childURL;
                document.body.append(frame);
                """, arguments: ["childURL": childURL.absoluteString, "allowsLocation": allowsLocation],
                in: nil, contentWorld: .page)
            if allowsLocation {
                try await waitUntil("the delegated frame's location requests") {
                    fixture.service.currentRequests.count == 1 && fixture.service.watchRequests.count == 1
                }
            } else {
                try await waitUntil("the undelegated frame's denial") {
                    try await fixture.page.webView.evaluateJavaScript("globalThis.frameDenied === true") as? Bool
                        == true
                }
                XCTAssertTrue(fixture.service.currentRequests.isEmpty)
                XCTAssertTrue(fixture.service.watchRequests.isEmpty)
            }
        }
    }

    func testSandboxedFrameCannotReuseLocationGrantButAllowedFrameStillWorks() async throws {
        for sandbox in ["allow-scripts", "allow-scripts allow-same-origin"] {
            let fixture = try makeFixture()
            defer { fixture.page.release(keepingState: false) }
            fixture.page.webView.loadSimulatedRequest(
                URLRequest(url: fixture.url), responseHTML: "<html>Frames</html>")
            try await waitUntil("the frame host") {
                fixture.page.webView.url == fixture.url && !fixture.page.webView.isLoading
            }
            _ = try await fixture.page.webView.callAsyncJavaScript(
                """
                globalThis.frameReported = false;
                addEventListener('message', () => { globalThis.frameReported = true; }, { once: true });
                const frame = document.createElement('iframe');
                frame.sandbox = sandbox;
                frame.srcdoc = `<script>
                  webkit.messageHandlers.crestGeolocation.postMessage({
                    version: 1, action: 'watchPosition', documentIdentifier: crypto.randomUUID(), identifier: 'frame'
                  });
                  parent.postMessage('requested', '*');
                </script>`;
                document.body.append(frame);
                """, arguments: ["sandbox": sandbox], in: nil, contentWorld: .page)
            try await waitUntil("the frame request") {
                try await fixture.page.webView.evaluateJavaScript("globalThis.frameReported === true") as? Bool == true
            }
            if sandbox.contains("allow-same-origin") {
                try await waitUntil("the permitted frame's native watch") { fixture.service.watchRequests.count == 1 }
            } else {
                try await Task.sleep(for: .milliseconds(150))
                XCTAssertTrue(fixture.service.watchRequests.isEmpty)
            }
        }
    }

    func testRevocationStopsRequestsAndRejectsLateCallbacksAfterRegrant() async throws {
        for action in Revocation.allCases {
            let fixture = try makeFixture()
            defer { fixture.page.release(keepingState: false) }
            let origin = try XCTUnwrap(SiteOrigin(url: fixture.url))
            try await loadRequests(in: fixture)
            let current = try XCTUnwrap(fixture.service.currentRequests.first?.value)
            let watch = try XCTUnwrap(fixture.service.watchRequests.first?.value)
            switch action {
            case .block, .ask:
                fixture.page.permissionCenter.setDecision(
                    action == .block ? .denyPersistently : .ask,
                    for: .location, origin: origin, in: fixture.page.spaceID
                )
            case .originReset:
                fixture.page.permissionCenter.reset(
                    recordID: try XCTUnwrap(
                        fixture.page.permissionCenter.records(in: fixture.page.spaceID).first?.id
                    ))
            case .spaceReset:
                fixture.page.permissionCenter.reset(spaceID: fixture.page.spaceID)
            }
            XCTAssertTrue(
                fixture.service.currentRequests.isEmpty, "\(action) cancels in-flight positions synchronously")
            XCTAssertTrue(fixture.service.watchRequests.isEmpty, "\(action) stops the native watch synchronously")
            fixture.page.permissionCenter.setDecision(
                .grantPersistently, for: .location, origin: origin, in: fixture.page.spaceID
            )
            current.receive(.success(Self.position))
            watch.receive(.success(Self.position))
            try await expectCounts(in: fixture, successes: 0, denials: 2)
            _ = try await fixture.page.webView.evaluateJavaScript(
                "navigator.geolocation.getCurrentPosition(success, failure);"
            )
            try await waitUntil("a fresh request after regrant") { fixture.service.currentRequests.count == 1 }
            try XCTUnwrap(fixture.service.currentRequests.first?.value).receive(.success(Self.position))
            try await expectCounts(in: fixture, successes: 1, denials: 2)
        }
    }

    func testLatePositionCannotReachAReplacementFrameAndNewRequestsStillWork() async throws {
        let fixture = try makeFixture()
        defer { fixture.page.release(keepingState: false) }
        fixture.page.webView.loadSimulatedRequest(URLRequest(url: fixture.url), responseHTML: "<html>Frames</html>")
        try await waitUntil("the frame host") {
            fixture.page.webView.url == fixture.url && !fixture.page.webView.isLoading
        }
        _ = try await fixture.page.webView.callAsyncJavaScript(
            """
            globalThis.messages = [];
            addEventListener('message', event => messages.push(event.data));
            const frame = document.createElement('iframe');
            frame.srcdoc = `<script>
              navigator.geolocation.watchPosition(() => parent.postMessage('old-position', '*'));
            </script>`;
            document.body.append(frame);
            """, arguments: [:], in: nil, contentWorld: .page)
        try await waitUntil("the original watch") { fixture.service.watchRequests.count == 1 }
        let oldWatch = try XCTUnwrap(fixture.service.watchRequests.first?.value)
        _ = try await fixture.page.webView.evaluateJavaScript(
            """
            document.querySelector('iframe').srcdoc = `<script>
              addEventListener('__crestGeolocationReply', () => parent.postMessage('leaked-position', '*'));
              parent.postMessage('replacement-ready', '*');
            </script>`;
            true;
            """)
        try await waitUntil("the replacement document") {
            try await fixture.page.webView.evaluateJavaScript("messages.includes('replacement-ready')") as? Bool == true
        }
        oldWatch.receive(.success(Self.position))
        try await waitUntil("the rejected old watch") { fixture.service.watchRequests.isEmpty }
        let leaked = try await fixture.page.webView.evaluateJavaScript(
            "messages.includes('old-position') || messages.includes('leaked-position')")
        XCTAssertEqual(leaked as? Bool, false)

        _ = try await fixture.page.webView.evaluateJavaScript(
            "frames[0].navigator.geolocation.getCurrentPosition(() => parent.postMessage('new-position', '*')); true;")
        try await waitUntil("the replacement's fresh request") { fixture.service.currentRequests.count == 1 }
        try XCTUnwrap(fixture.service.currentRequests.first?.value).receive(.success(Self.position))
        try await waitUntil("the replacement's authorized position") {
            try await fixture.page.webView.evaluateJavaScript("messages.includes('new-position')") as? Bool == true
        }
    }

    private enum Revocation: CaseIterable { case block, ask, originReset, spaceReset }
    /// The page, and the window that opened it through the core, which lives as
    /// long as the page.
    private typealias Fixture = (
        page: BrowserPage, service: TestBrowserGeolocationService, url: URL, browser: BrowserStore
    )

    private func loadRequests(in fixture: Fixture, startsAuthorized: Bool = true, watchOnly: Bool = false) async throws
    {
        fixture.page.webView.loadSimulatedRequest(URLRequest(url: fixture.url), responseHTML: "<title>Location</title>")
        try await waitUntil("the location document") {
            guard fixture.page.webView.url == fixture.url, !fixture.page.webView.isLoading else { return false }
            return try await self.permissionState(in: fixture.page.webView) == (startsAuthorized ? "granted" : "prompt")
        }
        _ = try await fixture.page.webView.evaluateJavaScript(
            """
            globalThis.successes = 0; globalThis.denials = 0;
            globalThis.success = () => { globalThis.successes++; };
            globalThis.failure = e => { if (e.code === 1) globalThis.denials++; };
            globalThis.watchID = navigator.geolocation.watchPosition(success, failure);
            """)
        if !watchOnly {
            _ = try await fixture.page.webView.evaluateJavaScript(
                "navigator.geolocation.getCurrentPosition(success, failure);")
        }
        if startsAuthorized {
            try await waitUntil("the native requests") {
                fixture.service.watchRequests.count == 1 && (watchOnly || fixture.service.currentRequests.count == 1)
            }
        }
    }

    private func expectCounts(in fixture: Fixture, successes: Double, denials: Double) async throws {
        try await waitUntil("\(denials) permission denials and \(successes) successes") {
            let counts =
                try await fixture.page.webView.evaluateJavaScript("[globalThis.successes, globalThis.denials]")
                as? [Double]
            return counts == [successes, denials]
        }
    }

    private static let position = BrowserGeolocationPosition(
        latitude: 41.8781,
        longitude: -87.6298,
        accuracy: 12,
        altitude: nil,
        altitudeAccuracy: nil,
        heading: nil,
        speed: nil,
        timestamp: 1_786_944_000_000
    )

    private func makeFixture(
        systemAuthorization: BrowserSystemAuthorization = .authorized,
        recoversSystemAuthorization: Bool = false,
        url: URL? = nil,
        space: SpaceState.Seed? = nil
    ) throws -> Fixture {
        let url = try XCTUnwrap(url ?? URL(string: "https://location.crest.test/"))
        let origin = try XCTUnwrap(SiteOrigin(url: url))
        let space = try XCTUnwrap(space ?? SessionState.Seed.preview.spaces.first)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        // The Space's choices live in the core that hosts the page, as in the app.
        let permissionCenter = BrowserSitePermissionCenter(core: browser.core)
        permissionCenter.setDecision(
            .grantPersistently,
            for: .location,
            origin: origin,
            in: space.id
        )
        let service = TestBrowserGeolocationService(
            authorization: systemAuthorization
        )
        let page = try XCTUnwrap(
            browser.openWebKitPage(in: space.id, for: nil).map {
                opened in
                BrowserPage(
                    corePage: opened.core,
                    webKitPage: opened.webKit,
                    dialogPresenter: BrowserDialogPresenter(),
                    downloadCenter: BrowserDownloadCenter(),
                    permissionCenter: permissionCenter,
                    geolocationService: service,
                    recoverGeolocationSystemAuthorization: {
                        service.recoveryCount += 1
                        if recoversSystemAuthorization {
                            service.authorization = .authorized
                        }
                    },
                    spaceID: space.id,
                    profileID: space.profileID,
                    spaceName: space.settings.name
                )
            })
        return (page, service, url, browser)
    }

    private func permissionState(in webView: WKWebView) async throws -> String? {
        try await webView.callAsyncJavaScript(
            "return (await navigator.permissions.query({ name: 'geolocation' })).state;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(5),
        condition: () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for \(description).")
    }
}

@MainActor
private final class TestBrowserGeolocationService: BrowserGeolocationServicing {
    struct Request {
        let options: BrowserGeolocationRequestOptions
        let receive: @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    }

    var currentRequests: [String: Request] = [:]
    var watchRequests: [String: Request] = [:]
    var cancelledIdentifiers: Set<String> = []
    var authorization: BrowserSystemAuthorization
    var recoveryCount = 0
    var delaysAuthorization = false
    var authorizationContinuation: CheckedContinuation<BrowserSystemAuthorization, Never>?

    init(authorization: BrowserSystemAuthorization) {
        self.authorization = authorization
    }

    func currentAuthorization() -> BrowserSystemAuthorization {
        authorization
    }

    func requestAuthorization() async -> BrowserSystemAuthorization {
        if delaysAuthorization {
            return await withCheckedContinuation { authorizationContinuation = $0 }
        }
        return authorization
    }

    func requestCurrentPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    ) {
        currentRequests[identifier] = Request(options: options, receive: receive)
    }

    func startWatchingPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    ) {
        watchRequests[identifier] = Request(options: options, receive: receive)
    }

    func cancel(identifier: String) {
        currentRequests.removeValue(forKey: identifier)
        watchRequests.removeValue(forKey: identifier)
        cancelledIdentifiers.insert(identifier)
    }

    func cancelAll() {
        currentRequests.removeAll()
        watchRequests.removeAll()
    }
}
