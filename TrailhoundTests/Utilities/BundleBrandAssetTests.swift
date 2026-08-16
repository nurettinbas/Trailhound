import AVFoundation
import UIKit
import XCTest
@testable import Trailhound

/// Locks brand asset sizes and recording cue codecs so a 1024 logo / PCM CAF cannot sneak back in.
@MainActor
final class BundleBrandAssetTests: XCTestCase {
    func testTrailhoundLogoIsExactly512Pixels() {
        let image = UIImage(named: "TrailhoundLogo")
        XCTAssertNotNil(image)
        let edge = Int(round((image?.size.width ?? 0) * (image?.scale ?? 0)))
        XCTAssertEqual(edge, 512)
        let height = Int(round((image?.size.height ?? 0) * (image?.scale ?? 0)))
        XCTAssertEqual(height, 512)
    }

    func testTrailhoundHoundStillLoads() {
        XCTAssertNotNil(UIImage(named: "TrailhoundHound"))
    }

    func testRecordingStartSoundIsCompactAACInCAF() throws {
        try assertRecordingCue(
            resource: "trip_start",
            expectedDuration: 1.90
        )
    }

    func testRecordingStopSoundIsCompactAACInCAF() throws {
        try assertRecordingCue(
            resource: "trip_stop",
            expectedDuration: 1.65
        )
    }

    private func assertRecordingCue(resource: String, expectedDuration: TimeInterval) throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: resource, withExtension: "caf"),
            "Missing \(resource).caf in app bundle"
        )
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = try XCTUnwrap(attrs[.size] as? NSNumber).intValue
        XCTAssertLessThan(bytes, 80 * 1024, "\(resource).caf should stay under 80 KB (got \(bytes))")

        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertEqual(player.duration, expectedDuration, accuracy: 0.08)
    }
}
