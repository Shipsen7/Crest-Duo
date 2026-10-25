import XCTest

@testable import Crest

@MainActor
final class BrowserSoftwareUpdateTests: XCTestCase {
    func testPrivateBuildHasNoPublisherTrustAndKeepsSignatureRequirements() {
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL"))
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey"))
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SURequireSignedFeed") as? Bool, true)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SUVerifyUpdateBeforeExtraction") as? Bool, true)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool, false)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SUAutomaticallyUpdate") as? Bool, false)
    }

    func testEveryChannelRefusesAFeedWithoutTheForksOwnPublisher() {
        for channel in BrowserSoftwareUpdateChannel.all {
            XCTAssertNil(channel.feedURL(for: .chromium), channel.name)
            XCTAssertNil(channel.feedURL(for: .webKit), channel.name)
        }
    }

    func testPrivateBuildCannotStartTheUpdaterEvenWhenRequested() {
        let service = BrowserSoftwareUpdateService(isEnabled: true, preferences: nil)
        XCTAssertFalse(service.isEnabled)
        XCTAssertNil(service.startErrorDescription)
    }

    func testInstallingAnArtifactFromAnotherChannelAdoptsItsBundledChannel() {
        let suiteName = "BrowserSoftwareUpdateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(
            BrowserSoftwareUpdateChannel.stable.name,
            forKey: BrowserSoftwareUpdateService.channelPreferenceKey
        )
        preferences.set(
            BrowserSoftwareUpdateChannel.stable.name,
            forKey: BrowserSoftwareUpdateService.bundledChannelPreferenceKey
        )

        let service = BrowserSoftwareUpdateService(
            isEnabled: false,
            preferences: preferences,
            defaultChannel: .development
        )

        XCTAssertEqual(service.channel, .development)
        XCTAssertEqual(
            preferences.string(
                forKey: BrowserSoftwareUpdateService.channelPreferenceKey
            ),
            BrowserSoftwareUpdateChannel.development.name
        )
    }

    func testUserChoiceSurvivesRelaunchesOfTheSameArtifactChannel() {
        let suiteName = "BrowserSoftwareUpdateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(
            BrowserSoftwareUpdateChannel.nightly.name,
            forKey: BrowserSoftwareUpdateService.channelPreferenceKey
        )
        preferences.set(
            BrowserSoftwareUpdateChannel.development.name,
            forKey: BrowserSoftwareUpdateService.bundledChannelPreferenceKey
        )

        let service = BrowserSoftwareUpdateService(
            isEnabled: false,
            preferences: preferences,
            defaultChannel: .development
        )

        XCTAssertEqual(service.channel, .nightly)
    }

}
