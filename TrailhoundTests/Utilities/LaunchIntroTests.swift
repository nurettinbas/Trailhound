import SwiftUI
import XCTest
@testable import Trailhound

final class LaunchIntroTimelineTests: XCTestCase {
    func testStandardBeatsAreOrderedAndShort() {
        let timeline = LaunchIntroTimeline.standard
        assertOrdered(timeline)
        XCTAssertEqual(timeline.total, 1.715, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(timeline.closeEnd - timeline.runEnd, 0.5, "the close needs room to read")
        XCTAssertLessThanOrEqual(timeline.total - timeline.closeEnd, 0.4, "the exit stays quick")
        XCTAssertTrue(timeline.allowsMotion)
        XCTAssertEqual(timeline.preferredFrameRate, 120)
    }

    func testReduceMotionIsAStillCrossfade() {
        let timeline = LaunchIntroTimeline.reduceMotion
        XCTAssertFalse(timeline.allowsMotion)
        XCTAssertEqual(timeline.total, TrailhoundMotion.launchIntroReduceMotionDuration, accuracy: 0.001)
    }

    func testLowPowerIsShorterAt60Hz() {
        let timeline = LaunchIntroTimeline.lowPower
        assertOrdered(timeline)
        XCTAssertEqual(timeline.total, TrailhoundMotion.launchIntroLowPowerDuration, accuracy: 0.001)
        XCTAssertLessThan(timeline.total, LaunchIntroTimeline.standard.total)
        XCTAssertTrue(timeline.allowsMotion)
        XCTAssertEqual(timeline.preferredFrameRate, 60)
    }

    func testSkipIsAQuarterSecond() {
        let timeline = LaunchIntroTimeline.skip
        XCTAssertEqual(timeline.total, TrailhoundMotion.launchIntroSkipDuration, accuracy: 0.001)
        XCTAssertFalse(timeline.allowsMotion)
        XCTAssertEqual(LaunchIntroTimeline.resolve(reduceMotion: true, lowPower: true).total, LaunchIntroTimeline.reduceMotion.total)
        XCTAssertEqual(LaunchIntroTimeline.resolve(reduceMotion: false, lowPower: true).total, LaunchIntroTimeline.lowPower.total)
    }

    private func assertOrdered(_ timeline: LaunchIntroTimeline, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(timeline.enterEnd, 0, file: file, line: line)
        XCTAssertLessThan(timeline.enterEnd, timeline.runEnd, file: file, line: line)
        XCTAssertLessThan(timeline.runEnd, timeline.closeEnd, file: file, line: line)
        XCTAssertLessThan(timeline.closeEnd, timeline.total, file: file, line: line)
    }
}

final class LaunchIntroGateTests: XCTestCase {
    func testPlaysOnANormalColdLaunch() {
        let decision = LaunchIntroGate.decide(
            isUITesting: false,
            isActiveRecording: false,
            hasPendingRecordingRequest: false,
            openedFromURL: false,
            openedFromNotification: false,
            voiceOver: false,
            alreadyPlayed: false,
            isFirstScene: true
        )
        XCTAssertTrue(decision.plays)
        XCTAssertNil(decision.skipReason)
    }

    func testEachSkipReason() {
        XCTAssertEqual(decide(isUITesting: true).skipReason, .uiTest)
        XCTAssertEqual(decide(isActiveRecording: true).skipReason, .activeRecording)
        XCTAssertEqual(decide(hasPendingRecordingRequest: true).skipReason, .pendingRecordingRequest)
        XCTAssertEqual(decide(openedFromURL: true).skipReason, .openedFromURL)
        XCTAssertEqual(decide(openedFromNotification: true).skipReason, .notificationTap)
        XCTAssertEqual(decide(voiceOver: true).skipReason, .voiceOver)
        XCTAssertEqual(decide(alreadyPlayed: true).skipReason, .alreadyPlayed)
        XCTAssertEqual(decide(isFirstScene: false).skipReason, .secondaryScene)
    }

    private func decide(
        isUITesting: Bool = false,
        isActiveRecording: Bool = false,
        hasPendingRecordingRequest: Bool = false,
        openedFromURL: Bool = false,
        openedFromNotification: Bool = false,
        voiceOver: Bool = false,
        alreadyPlayed: Bool = false,
        isFirstScene: Bool = true
    ) -> LaunchIntroDecision {
        LaunchIntroGate.decide(
            isUITesting: isUITesting,
            isActiveRecording: isActiveRecording,
            hasPendingRecordingRequest: hasPendingRecordingRequest,
            openedFromURL: openedFromURL,
            openedFromNotification: openedFromNotification,
            voiceOver: voiceOver,
            alreadyPlayed: alreadyPlayed,
            isFirstScene: isFirstScene
        )
    }
}