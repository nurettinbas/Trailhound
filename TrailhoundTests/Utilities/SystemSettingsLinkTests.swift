import XCTest
@testable import Trailhound

final class SystemSettingsLinkTests: XCTestCase {
    func testPublicSettingsURLIsTheSystemAppSettingsLink() {
        XCTAssertEqual(
            SystemSettingsLink.publicAppSettingsURL?.absoluteString,
            "app-settings:"
        )
    }
}
