import SwiftUI
import XCTest
@testable import Trailhound

final class TripDetailMapStyleTests: XCTestCase {
    func testMatchingFollowsSystemAppearance() {
        XCTAssertEqual(TripDetailMapStyle.matching(.light), .standard)
        XCTAssertEqual(TripDetailMapStyle.matching(.dark), .dark)
    }

    func testLightAlwaysForcesLightEvenWhenSystemIsDark() {
        XCTAssertEqual(TripDetailMapStyle.standard.forcedColorScheme, .light)
    }

    func testDarkAlwaysForcesDarkEvenWhenSystemIsLight() {
        XCTAssertEqual(TripDetailMapStyle.dark.forcedColorScheme, .dark)
    }
}
