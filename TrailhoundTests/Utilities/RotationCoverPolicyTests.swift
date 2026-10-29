import XCTest
@testable import Trailhound

final class RotationCoverPolicyTests: XCTestCase {
    func testOldScreenIsGoneBeforeTheTurnEnds() {
        XCTAssertGreaterThan(RotationCoverPolicy.fadeShare, 0.3)
        XCTAssertLessThan(RotationCoverPolicy.fadeShare, 1)
    }
}
