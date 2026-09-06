import SwiftUI
import XCTest
@testable import Trailhound

final class GlassPaletteTests: XCTestCase {
    func testDarkTextUsesSystemHierarchy() {
        XCTAssertEqual(GlassText.primary(for: .dark), Color.primary)
        XCTAssertEqual(GlassText.secondary(for: .dark), Color.secondary)
    }

    func testLightTextUsesWhiteHierarchy() {
        XCTAssertEqual(GlassText.primary(for: .light), LightGlassPalette.textPrimary)
        XCTAssertEqual(GlassText.secondary(for: .light), LightGlassPalette.textSecondary)
        XCTAssertEqual(GlassText.tertiary(for: .light), LightGlassPalette.textTertiary)
        XCTAssertEqual(GlassText.placeholder(for: .light), LightGlassPalette.textPlaceholder)
        XCTAssertEqual(GlassText.disabled(for: .light), LightGlassPalette.textDisabled)
    }

    func testDarkSemanticsStaySystem() {
        XCTAssertEqual(GlassSemantic.recording(for: .dark), Color.red)
        XCTAssertEqual(GlassSemantic.paused(for: .dark), Color.orange)
        XCTAssertEqual(GlassSemantic.success(for: .dark), Color.green)
        XCTAssertEqual(GlassSemantic.destructive(for: .dark), Color.red)
    }

    func testLightSemanticsUseLiftedPalette() {
        XCTAssertEqual(GlassSemantic.recording(for: .light), LightGlassPalette.recording)
        XCTAssertEqual(GlassSemantic.paused(for: .light), LightGlassPalette.paused)
        XCTAssertEqual(GlassSemantic.success(for: .light), LightGlassPalette.success)
        XCTAssertEqual(GlassSemantic.destructive(for: .light), LightGlassPalette.destructive)
    }

    func testRecordingCardFillFollowsPalette() {
        let sky = RecordingCardStyle.fillColors(isPaused: false, palette: .sky, scheme: .light)
        let rose = RecordingCardStyle.fillColors(isPaused: false, palette: .rose, scheme: .light)
        XCTAssertNotEqual(sky, rose)
        XCTAssertEqual(sky[1], ShellPalette.sky.tintColor(for: .light))
        XCTAssertEqual(rose[1], ShellPalette.rose.tintColor(for: .light))
    }

    func testNotificationBadgeIsOpaqueSystemRed() {
        XCTAssertEqual(
            GlassSemantic.notificationBadge,
            Color(red: 1.0, green: 0.231, blue: 0.188)
        )
        XCTAssertNotEqual(
            GlassSemantic.notificationBadge,
            LightGlassPalette.destructive
        )
        XCTAssertNotEqual(
            GlassSemantic.notificationBadge,
            ShellPalette.rose.tintColor(for: .light)
        )
    }

    func testAtmosphereTokensMatchSaturatedSkyBlue() {
        XCTAssertEqual(TrailhoundBrandColors.atmosphereTop, LightGlassPalette.atmosphereTop)
        XCTAssertEqual(TrailhoundBrandColors.atmosphereMid, LightGlassPalette.atmosphereMid)
        XCTAssertEqual(TrailhoundBrandColors.atmosphereBottom, LightGlassPalette.atmosphereBottom)
    }

    func testSegmentedTintFollowsPalette() {
        XCTAssertEqual(
            GlassControlTint.segmented(for: .light, palette: .forest),
            ShellPalette.forest.tintColor(for: .light)
        )
        XCTAssertEqual(
            GlassControlTint.segmented(for: .dark, palette: .sunset),
            ShellPalette.sunset.tintColor(for: .dark)
        )
        XCTAssertNotEqual(
            GlassControlTint.segmented(for: .light, palette: .forest),
            GlassControlTint.segmented(for: .light, palette: .sky)
        )
    }

    func testSelectedChipIsWhiteOnBlue() {
        XCTAssertEqual(LightGlassPalette.selectedChipFill, Color.white.opacity(0.92))
        XCTAssertEqual(
            LightGlassPalette.selectedChipText,
            Color(red: 0.122, green: 0.373, blue: 0.686)
        )
    }

    func testNativeGlassTintFollowsPalette() {
        let sky = LightGlassPalette.nativeTint(for: .sky)
        let magenta = LightGlassPalette.nativeTint(for: .magenta)
        XCTAssertNotEqual(sky, magenta)
        XCTAssertEqual(
            sky,
            ShellPalette.sky.tintColor(for: .light).opacity(LightGlassPalette.nativeGlassTintOpacity)
        )
    }
}
