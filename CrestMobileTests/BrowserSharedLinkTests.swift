import XCTest

@testable import CrestMobile

/// The share extension hands links to the app through a URL any app can
/// open, so these protect what that hand-off carries and accepts.
final class BrowserSharedLinkTests: XCTestCase {
    func testHandOffAcceptsOnlyAWebLinkThroughFennavioOpen() throws {
        let rejected = [
            "https://example.com",
            "crest://open?url=https%3A%2F%2Fexample.com",
            "fennavio://other?url=https%3A%2F%2Fexample.com",
            "fennavio://open/path?url=https%3A%2F%2Fexample.com",
            "fennavio://open",
            "fennavio://open?url=",
            "fennavio://open?url=javascript%3Aalert(1)",
            "fennavio://open?url=file%3A%2F%2F%2Fetc%2Fpasswd",
            "fennavio://open?url=data%3Atext%2Fhtml%2Chi",
            "fennavio://open?url=https%3A%2F%2F",
            "fennavio://open?url=crest%3A%2F%2Fopen%3Furl%3Dhttps%253A%252F%252Fexample.com",
            "fennavio://open?url=https%3A%2F%2Fa.com&url=https%3A%2F%2Fb.com",
        ]
        for string in rejected {
            let url = try XCTUnwrap(URL(string: string), string)
            XCTAssertNil(BrowserSharedLink(handOffURL: url), string)
        }

        let accepted = try XCTUnwrap(URL(string: "FENNAVIO://open?url=http%3A%2F%2Fexample.com&later=1"))
        XCTAssertEqual(BrowserSharedLink(handOffURL: accepted)?.url.absoluteString, "http://example.com")
    }
}
