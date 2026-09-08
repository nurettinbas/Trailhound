import XCTest
@testable import Trailhound

final class AchievementThemeTests: XCTestCase {
    func testEveryAchievementMapsToAFamily() {
        for id in AchievementID.allCases {
            _ = id.family
            XCTAssertGreaterThanOrEqual(id.familyTier, 0)
        }
        XCTAssertEqual(Set(AchievementID.allCases.map(\.family)).count, AchievementFamily.allCases.count)
    }

    func testListOrderPutsUnlockedFirst() {
        let lockedFirst = AchievementDisplay(id: .firstTrip, currentValue: 0, unlockedAt: nil, needsCelebration: false)
        let unlockedLate = AchievementDisplay(id: .routesRegular, currentValue: 10, unlockedAt: Date(), needsCelebration: false)
        let unlockedEarly = AchievementDisplay(id: .distance100, currentValue: 100_000, unlockedAt: Date(), needsCelebration: false)
        let lockedLate = AchievementDisplay(id: .nightOwl, currentValue: 0, unlockedAt: nil, needsCelebration: false)
        let ordered = [lockedFirst, unlockedLate, unlockedEarly, lockedLate].sorted(by: AchievementDisplay.listOrder)
        XCTAssertEqual(ordered.map(\.id), [.distance100, .routesRegular, .firstTrip, .nightOwl])
    }

    func testFamilyHuesAreUnique() {
        let hues = AchievementFamily.allCases.map { AchievementTheme.familyHue(for: $0) }
        XCTAssertEqual(Set(hues).count, hues.count)
    }

    func testDistanceTiersShareFamilyAndIncreaseStrength() {
        XCTAssertEqual(AchievementID.distance100.family, .distance)
        XCTAssertEqual(AchievementID.distance1000.family, .distance)
        XCTAssertEqual(AchievementID.distance10000.family, .distance)
        XCTAssertEqual(AchievementID.distance100000.family, .distance)
        XCTAssertLessThan(AchievementID.distance100.familyTier, AchievementID.distance1000.familyTier)
        XCTAssertLessThan(AchievementID.distance1000.familyTier, AchievementID.distance10000.familyTier)
        XCTAssertLessThan(AchievementID.distance10000.familyTier, AchievementID.distance100000.familyTier)
    }

    func testDistanceMaterialsAreMetalLadder() {
        XCTAssertEqual(AchievementID.distance100.medalMaterial, .silver)
        XCTAssertEqual(AchievementID.distance1000.medalMaterial, .gold)
        XCTAssertEqual(AchievementID.distance10000.medalMaterial, .platinum)
        XCTAssertEqual(AchievementID.distance100000.medalMaterial, .diamond)
        XCTAssertNil(AchievementID.firstTrip.medalMaterial)
        XCTAssertNil(AchievementID.business10.medalMaterial)
        XCTAssertNil(AchievementID.nightOwl.medalMaterial)
    }

    func testPlatinumChromeIsTealNotGray() {
        let accent = AchievementPlatinumSwatch.faceAccentDark
        let red = (accent >> 16) & 0xFF
        let green = (accent >> 8) & 0xFF
        let blue = accent & 0xFF
        XCTAssertGreaterThan(green, red)
        XCTAssertGreaterThan(blue, red)
        XCTAssertGreaterThan(green, 140)
        XCTAssertEqual(AchievementPlatinumSwatch.faceAccentDark, 0x14B2AA)
        XCTAssertEqual(AchievementPlatinumSwatch.faceAccentLight, 0x20C4BC)
    }

    func testDiamondChromeIsPurpleNotIce() {
        let accent = AchievementDiamondSwatch.faceAccentDark
        let red = (accent >> 16) & 0xFF
        let green = (accent >> 8) & 0xFF
        let blue = accent & 0xFF
        XCTAssertGreaterThan(red, green)
        XCTAssertGreaterThan(blue, green)
        XCTAssertGreaterThan(blue, 200)
        XCTAssertEqual(AchievementDiamondSwatch.faceAccentDark, 0xB794F6)
        XCTAssertEqual(AchievementDiamondSwatch.faceAccentLight, 0xC4B5FD)
        XCTAssertTrue(AchievementID.distance100000.listsWhilePredecessorLocked)
        XCTAssertFalse(AchievementID.business50.listsWhilePredecessorLocked)
    }

    func testDistance100000Catalog() {
        XCTAssertEqual(AchievementID.distance100000.rawValue, "distance.100000")
        XCTAssertEqual(AchievementID.distance100000.threshold, 100_000_000)
        XCTAssertEqual(AchievementID.distance100000.predecessor, .distance10000)
        XCTAssertEqual(AchievementID.distance100000.progressKind, .distanceMeters)
        XCTAssertEqual(AchievementID.distance100000.familyTier, 3)
    }

    func testDistance100000CaptionUsesFormattedKilometersNotRawMeters() {
        let text = AchievementProgressCaption.text(
            current: 50_000_000,
            threshold: 100_000_000,
            kind: .distanceMeters
        )
        XCTAssertFalse(text.contains("50000000"))
        XCTAssertFalse(text.contains("100000000"))
        XCTAssertEqual(
            text,
            "\(DateFormatters.formatDistance(50_000_000)) / \(DateFormatters.formatDistance(100_000_000))"
        )
    }

    func testDistanceCaptionUsesFormattedKilometersNotRawMeters() {
        let text = AchievementProgressCaption.text(
            current: 50_000,
            threshold: 100_000,
            kind: .distanceMeters
        )
        XCTAssertFalse(text.contains("50000"))
        XCTAssertFalse(text.contains("100000"))
        XCTAssertTrue(text.contains(" / "))
        XCTAssertEqual(
            text,
            "\(DateFormatters.formatDistance(50_000)) / \(DateFormatters.formatDistance(100_000))"
        )
    }

    func testCountCaptionUsesWholeNumbers() {
        XCTAssertEqual(
            AchievementProgressCaption.text(current: 3.2, threshold: 10, kind: .count),
            "3 / 10"
        )
    }

    func testNightOwlUsesDistanceCaption() {
        XCTAssertEqual(AchievementID.nightOwl.progressKind, .distanceMeters)
        XCTAssertEqual(AchievementID.cities10.progressKind, .count)
    }

    func testLockedOverlayKeepsSaturatedMedal() {
        XCTAssertEqual(AchievementTheme.lockScrimOpacity, 0.45)
        XCTAssertEqual(AchievementMedalLockOverlay.lockGlyphSize(for: 52), max(13, 52 * 0.36))
        XCTAssertEqual(AchievementMedalLockOverlay.lockGlyphSize(for: 48), max(13, 48 * 0.36))
        XCTAssertFalse(AchievementMedalIdle.discTilts(.firstTrip))
        XCTAssertFalse(AchievementMedalIdle.discTilts(.distance))
        XCTAssertFalse(AchievementMedalIdle.discTilts(.night))
        XCTAssertTrue(AchievementMedalIdle.discTilts(.routes))
        XCTAssertEqual(AchievementMedalIdle.flagWaveDuration, 0.72, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.flagWaveSwayDegrees, 36, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.flagWaveFold, 0.24, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.flagWaveFlapDegrees, 12, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.pathTravelDuration, 1.45, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.nightBobDuration, 1.8, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.nightBobAmplitude(for: 48), 48 * 0.06, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.nightBobAmplitude(for: 20), 2, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.nightBobAmplitude(for: 128), 4, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.nightSparkleDuration, 0.55, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.pingPong(at: 0, duration: 1), 0, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.pingPong(at: 1, duration: 1), 1, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.pingPong(at: 2, duration: 1), 0, accuracy: 0.001)
        XCTAssertEqual(AchievementMedalIdle.compactClockInterval, 1.0 / 12.0, accuracy: 0.0001)
    }

    func testDistancePathTravelsBottomLeftToTopRight() {
        let size = CGSize(width: 100, height: 100)
        let start = AchievementDistancePath.point(at: 0, in: size)
        let end = AchievementDistancePath.point(at: 1, in: size)
        XCTAssertLessThan(start.x, 40)
        XCTAssertGreaterThan(start.y, 60)
        XCTAssertGreaterThan(end.x, 60)
        XCTAssertLessThan(end.y, 40)
        let mid = AchievementDistancePath.point(at: 0.5, in: size)
        XCTAssertEqual(mid.x, 50, accuracy: 18)
        XCTAssertEqual(AchievementDistancePath.point(at: 0, in: size), AchievementDistancePath.start(in: size))
        XCTAssertEqual(AchievementDistancePath.point(at: 1, in: size), AchievementDistancePath.end(in: size))
    }

    func testDistancePathMotionLadder() {
        XCTAssertEqual(AchievementDistancePathMotion.for(.silver), .convoy)
        XCTAssertEqual(AchievementDistancePathMotion.for(.gold), .rendezvous)
        XCTAssertEqual(AchievementDistancePathMotion.for(.platinum), .patrol)
        XCTAssertEqual(AchievementDistancePathMotion.for(.diamond), .bloom)
        XCTAssertLessThan(AchievementDistancePathMotion.convoy.duration, AchievementDistancePathMotion.rendezvous.duration)
        XCTAssertLessThan(AchievementDistancePathMotion.rendezvous.duration, AchievementDistancePathMotion.patrol.duration)
        XCTAssertLessThan(AchievementDistancePathMotion.patrol.duration, AchievementDistancePathMotion.bloom.duration)

        let convoyStart = (
            AchievementDistancePathMotion.convoy.nodeProgress(phase: 0, index: 0),
            AchievementDistancePathMotion.convoy.nodeProgress(phase: 0, index: 1)
        )
        XCTAssertEqual(convoyStart.0, 0, accuracy: 0.001)
        XCTAssertGreaterThan(convoyStart.1, convoyStart.0)
        XCTAssertEqual(AchievementDistancePathMotion.convoy.nodeProgress(phase: 1, index: 0), 1, accuracy: 0.001)

        XCTAssertEqual(AchievementDistancePathMotion.rendezvous.nodeProgress(phase: 0, index: 0), 0, accuracy: 0.001)
        XCTAssertEqual(AchievementDistancePathMotion.rendezvous.nodeProgress(phase: 0, index: 1), 1, accuracy: 0.001)
        XCTAssertEqual(AchievementDistancePathMotion.rendezvous.nodeProgress(phase: 0.5, index: 0), 0.5, accuracy: 0.001)
        XCTAssertEqual(AchievementDistancePathMotion.rendezvous.nodeProgress(phase: 0.5, index: 1), 0.5, accuracy: 0.001)

        let patrolMid = (
            AchievementDistancePathMotion.patrol.nodeProgress(phase: 1, index: 0),
            AchievementDistancePathMotion.patrol.nodeProgress(phase: 1, index: 1)
        )
        XCTAssertLessThan(patrolMid.0, 0.5)
        XCTAssertGreaterThan(patrolMid.1, 0.5)

        XCTAssertEqual(AchievementDistancePathMotion.bloom.nodeProgress(phase: 0, index: 0), 0.5, accuracy: 0.001)
        XCTAssertEqual(AchievementDistancePathMotion.bloom.nodeProgress(phase: 0, index: 1), 0.5, accuracy: 0.001)
        XCTAssertEqual(AchievementDistancePathMotion.bloom.nodeProgress(phase: 1, index: 0), 0, accuracy: 0.001)
        XCTAssertEqual(AchievementDistancePathMotion.bloom.nodeProgress(phase: 1, index: 1), 1, accuracy: 0.001)
    }

    func testGalleryCardsStayCompact() {
        XCTAssertLessThan(AchievementGalleryTokens.cardHeight, 220)
        XCTAssertLessThanOrEqual(AchievementGalleryTokens.bodySlotHeight, 32)
        XCTAssertLessThanOrEqual(AchievementGalleryTokens.medalSize, 48)
    }

    func testGalleryExpandGrowsFromSourceFrame() {
        let source = CGRect(x: 16, y: 240, width: 358, height: 96)
        let overlay = CGRect(x: 0, y: 0, width: 390, height: 844)
        XCTAssertEqual(
            AchievementGalleryExpandLayout.localSurface(sourceGlobal: source, overlayGlobal: overlay, expanded: false),
            source
        )
        XCTAssertEqual(
            AchievementGalleryExpandLayout.localSurface(sourceGlobal: source, overlayGlobal: overlay, expanded: true),
            CGRect(origin: .zero, size: overlay.size)
        )
        XCTAssertEqual(AchievementGalleryExpandLayout.cornerRadius(expanded: false), StatsCardTokens.radius)
        XCTAssertEqual(AchievementGalleryExpandLayout.cornerRadius(expanded: true), 0)
    }

    func testGalleryExpandMissingSourceFillsOverlay() {
        let overlay = CGRect(x: 0, y: -20, width: 390, height: 884)
        let filled = CGRect(origin: .zero, size: overlay.size)
        XCTAssertEqual(
            AchievementGalleryExpandLayout.localSurface(sourceGlobal: .zero, overlayGlobal: overlay, expanded: false),
            filled
        )
        XCTAssertFalse(AchievementGalleryExpandLayout.hasUsableSource(.zero))
        XCTAssertNil(TrailhoundMotion.badgeCardExpand(reduceMotion: true))
        XCTAssertNotNil(TrailhoundMotion.badgeCardExpand(reduceMotion: false))
    }
}
