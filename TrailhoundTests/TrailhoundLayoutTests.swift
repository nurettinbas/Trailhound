import SwiftUI
import UIKit
import XCTest
@testable import Trailhound

final class TrailhoundLayoutTests: XCTestCase {
    func testPhonePortraitStaysPhone() {
        let resolved = TrailhoundLayoutResolver.resolve(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 390, height: 844),
            idiom: .phone,
            debugOverride: nil
        )
        XCTAssertEqual(resolved, .phone)
    }

    func testPhoneLandscape() {
        let resolved = TrailhoundLayoutResolver.resolve(
            horizontal: .compact,
            vertical: .compact,
            size: CGSize(width: 844, height: 390),
            idiom: .phone,
            debugOverride: nil
        )
        XCTAssertEqual(resolved, .phoneLandscape)
    }

    func testOpenFoldPortraitPinsTheRecordingCardToAHorizontalHinge() {
        let compactWide = TrailhoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 402, height: 1600),
            idiom: .phone
        )
        XCTAssertEqual(compactWide.layoutClass, .duoOpen)
        XCTAssertFalse(compactWide.isLandscape)
        XCTAssertTrue(compactWide.pinsRecordingCardToFold)
        XCTAssertFalse(compactWide.splitsTrips)
        XCTAssertFalse(compactWide.splitsIdleLibrary)
        XCTAssertTrue(compactWide.hidesRecordingCardFromList)

        let regularPortrait = TrailhoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 680, height: 1100),
            idiom: .phone
        )
        XCTAssertEqual(regularPortrait.layoutClass, .duoOpen)
        XCTAssertTrue(regularPortrait.pinsRecordingCardToFold)
        XCTAssertEqual(regularPortrait.duoSheetLeadingInset(matchingTrailingSafeArea: 80), GlassTokens.panelHorizontalInset)
        XCTAssertEqual(regularPortrait.duoSheetLeadingInset(matchingTrailingSafeArea: 0), 0)
        XCTAssertEqual(compactWide.duoSheetLeadingInset(matchingTrailingSafeArea: 80), GlassTokens.panelHorizontalInset)
    }

    func testClosedLandscapeKeepsTheRecordingCardInTheList() {
        let book = TrailhoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .compact,
            size: CGSize(width: 1600, height: 402),
            idiom: .phone
        )
        XCTAssertEqual(book.layoutClass, .phoneLandscape)
        XCTAssertTrue(book.splitsTrips)
        XCTAssertTrue(book.isWideBook)
        XCTAssertTrue(book.splitsIdleLibrary)
        XCTAssertFalse(book.splitsRecording)
        XCTAssertFalse(book.recordingCardLeads)
        XCTAssertFalse(book.pinsRecordingCardToFold)
        XCTAssertEqual(book.recordingCardArrangement, .list)
        XCTAssertFalse(book.hidesRecordingCardFromList)

        let phoneLand = TrailhoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .compact,
            size: CGSize(width: 844, height: 390),
            idiom: .phone
        )
        XCTAssertFalse(phoneLand.splitsIdleLibrary)
        XCTAssertFalse(phoneLand.splitsRecording)
        XCTAssertFalse(phoneLand.recordingCardLeads)
        XCTAssertEqual(phoneLand.recordingCardArrangement, .list)
        XCTAssertFalse(phoneLand.hidesRecordingCardFromList)
    }

    func testOpenBookLandscapePutsTheRecordingCardOnTheLeadingHalf() {
        let openBook = TrailhoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1600, height: 1100),
            idiom: .phone
        )
        XCTAssertEqual(openBook.layoutClass, .duoOpen)
        XCTAssertTrue(openBook.isLandscape)
        XCTAssertTrue(openBook.splitsTrips)
        XCTAssertTrue(openBook.isWideBook)
        XCTAssertTrue(openBook.splitsIdleLibrary)
        XCTAssertTrue(openBook.splitsRecording)
        XCTAssertTrue(openBook.recordingCardLeads)
        XCTAssertFalse(openBook.pinsRecordingCardToFold)
        XCTAssertEqual(openBook.recordingCardArrangement, .pane)
        XCTAssertTrue(openBook.hidesRecordingCardFromList)
    }

    func testOpenFoldLandscapeIsHalfMapHalfDetails() {
        let book = TrailhoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 1600, height: 402),
            idiom: .phone
        )
        XCTAssertEqual(book.layoutClass, .duoOpen)
        XCTAssertTrue(book.isLandscape)
        XCTAssertEqual(book.tripDetailStyle, .split)
        XCTAssertEqual(book.duoSheetLeadingInset(matchingTrailingSafeArea: 80), 0)

        let upright = TrailhoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 402, height: 1600),
            idiom: .phone
        )
        XCTAssertEqual(upright.tripDetailStyle, .overlay)
    }

    func testViewportJumpIsARotationNotASheet() {
        XCTAssertFalse(
            TrailhoundLayoutResolver.viewportChangeCancelsRotation(
                from: .zero,
                to: CGSize(width: 390, height: 844)
            )
        )
        XCTAssertFalse(
            TrailhoundLayoutResolver.viewportChangeCancelsRotation(
                from: CGSize(width: 390, height: 844),
                to: CGSize(width: 390, height: 780)
            )
        )
        XCTAssertTrue(
            TrailhoundLayoutResolver.viewportChangeCancelsRotation(
                from: CGSize(width: 402, height: 1600),
                to: CGSize(width: 1600, height: 402)
            )
        )
    }

    func testUprightDuoCentersOnboarding() {
        let duo = TrailhoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 620, height: 900),
            idiom: .phone
        )
        XCTAssertTrue(duo.centersOnboardingColumn)
        let turned = TrailhoundLayoutResolver.snapshot(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 900, height: 620),
            idiom: .phone
        )
        XCTAssertFalse(turned.centersOnboardingColumn)
        let squatFold = TrailhoundLayoutResolver.snapshot(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 620, height: 900),
            idiom: .phone
        )
        XCTAssertEqual(squatFold.layoutClass, .phone)
        XCTAssertTrue(squatFold.centersOnboardingColumn)
        XCTAssertFalse(TrailhoundLayoutSnapshot.phone.centersOnboardingColumn)
    }

    func testOpenInnerScreenIsDuo() {
        let resolved = TrailhoundLayoutResolver.resolve(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 844, height: 700),
            idiom: .phone,
            debugOverride: nil
        )
        XCTAssertEqual(resolved, .duoOpen)
    }

    func testPadAndNarrowSplit() {
        let pad = TrailhoundLayoutResolver.resolve(
            horizontal: .regular,
            vertical: .regular,
            size: CGSize(width: 1024, height: 1366),
            idiom: .pad,
            debugOverride: nil
        )
        XCTAssertEqual(pad, .pad)
        let split = TrailhoundLayoutResolver.resolve(
            horizontal: .compact,
            vertical: .regular,
            size: CGSize(width: 320, height: 800),
            idiom: .pad,
            debugOverride: nil
        )
        XCTAssertEqual(split, .phone)
    }

    func testColumnCountDoesNotStretchHalfTiles() {
        let phone = TrailhoundLayoutResolver.columnCount(layout: .phone, contentWidth: 358)
        XCTAssertEqual(phone, 2)
        let widePad = TrailhoundLayoutResolver.columnCount(layout: .pad, contentWidth: 1600)
        XCTAssertGreaterThanOrEqual(widePad, 4)
        let half = TrailhoundLayoutResolver.halfWidth(columns: widePad, contentWidth: 1600)
        XCTAssertLessThanOrEqual(half, GlassTokens.moduleMaxHalf + 0.5)
        XCTAssertGreaterThanOrEqual(half, GlassTokens.moduleMinHalf - 0.5)
    }

    func testDuoSplitLandsOnTheHingeWhenTheTabColumnInsetsTheTrailingEdge() {
        let window: CGFloat = 1000
        let tabColumn: CGFloat = 100
        let gutter: CGFloat = 24
        let leading = TrailhoundLayoutResolver.duoLeadingPaneWidth(
            contentOriginX: 0,
            contentWidth: window - tabColumn,
            windowWidth: window,
            gutter: gutter,
            listOnVisualLeft: true
        )
        XCTAssertEqual(leading, window / 2 - gutter / 2)
        let seam = leading + gutter / 2
        XCTAssertEqual(seam, window / 2)
    }

    func testDuoSplitLandsOnTheHingeWhenTheTabColumnInsetsTheLeadingEdge() {
        let window: CGFloat = 1000
        let tabColumn: CGFloat = 80
        let gutter: CGFloat = 24
        let leading = TrailhoundLayoutResolver.duoLeadingPaneWidth(
            contentOriginX: tabColumn,
            contentWidth: window - tabColumn,
            windowWidth: window,
            gutter: gutter,
            listOnVisualLeft: true
        )
        XCTAssertEqual(leading + tabColumn + gutter / 2, window / 2)
    }

    func testHingeGutterRejectsACardOnTheFold() {
        let container = CGSize(width: 844, height: 700)
        let hinge = TrailhoundLayoutResolver.hingeFrame(in: container)
        let straddling = CGRect(x: hinge.midX - 20, y: 40, width: 80, height: 120)
        let clear = CGRect(x: 16, y: 40, width: 300, height: 120)
        XCTAssertTrue(TrailhoundLayoutResolver.frameIntersectsHinge(straddling, container: container))
        XCTAssertFalse(TrailhoundLayoutResolver.frameIntersectsHinge(clear, container: container))
    }

    func testListLeadsAndMirrors() {
        XCTAssertTrue(TrailhoundLayoutResolver.listIsOnVisualLeft(direction: .leftToRight))
        XCTAssertFalse(TrailhoundLayoutResolver.listIsOnVisualLeft(direction: .rightToLeft))
    }

    func testBadgeColumns() {
        XCTAssertEqual(
            TrailhoundLayoutResolver.badgeColumnCount(layout: .phone, isLandscape: false, accessibility: false),
            2
        )
        XCTAssertEqual(
            TrailhoundLayoutResolver.badgeColumnCount(layout: .phoneLandscape, isLandscape: true, accessibility: false),
            4
        )
        XCTAssertEqual(
            TrailhoundLayoutResolver.badgeColumnCount(layout: .duoOpen, isLandscape: true, accessibility: false),
            4
        )
        XCTAssertEqual(
            TrailhoundLayoutResolver.badgeColumnCount(layout: .duoOpen, isLandscape: false, accessibility: false),
            3
        )
        XCTAssertEqual(
            TrailhoundLayoutResolver.badgeColumnCount(layout: .pad, isLandscape: false, accessibility: false),
            4
        )
        XCTAssertEqual(
            TrailhoundLayoutResolver.badgeColumnCount(layout: .pad, isLandscape: true, accessibility: false),
            6
        )
        XCTAssertEqual(
            TrailhoundLayoutResolver.badgeColumnCount(layout: .pad, isLandscape: true, accessibility: true),
            1
        )
    }

    func testLayoutReflowMatchesBadgeSpring() {
        XCTAssertNotNil(TrailhoundMotion.layoutReflow(reduceMotion: false))
        XCTAssertNotNil(TrailhoundMotion.layoutReflow(reduceMotion: true))
    }
}
