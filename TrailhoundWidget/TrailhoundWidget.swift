import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit

private enum WidgetL10n {
    private static func text(_ key: String) -> String {
        SharedL10n.text(key)
    }

    static var pause: String { text("action.pause") }
    static var resume: String { text("action.resume") }
    static var stop: String { text("action.stop") }
    static var start: String { text("action.start") }
    static var paused: String { text("live_activity.paused") }
    static var recording: String { text("live_activity.recording") }
    static var tripActive: String { text("live_activity.trip_active") }
    static var tripPaused: String { text("live_activity.trip_paused") }
    static var distance: String { text("label.distance") }
    static var duration: String { text("label.duration") }
    static var speed: String { text("live_activity.speed") }
    static var noRecording: String { text("widget.no_recording") }
    static var thisWeek: String { text("section.this_week") }
    static var displayName: String { text("widget.display_name") }
    static var description: String { text("widget.description") }
}

private enum WidgetPalette {
    static let brandTop = TrailhoundBrandColors.brandTop
    static let brandBottom = TrailhoundBrandColors.brandBottom
    static let recording = TrailhoundBrandColors.recording
    static let paused = TrailhoundBrandColors.paused
    static let resume = TrailhoundBrandColors.resume
    static let stop = TrailhoundBrandColors.stop
    static let start = TrailhoundBrandColors.start
}

private struct WidgetAdaptiveBackground: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        if renderingMode == .fullColor {
            LinearGradient(
                colors: [WidgetPalette.brandTop.opacity(0.28), WidgetPalette.brandBottom.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct WidgetIntentButton<Intent: AppIntent>: View {
    enum Size {
        case regular
        case small
    }

    let title: String
    let systemImage: String
    let tint: Color
    let size: Size
    let iconOnly: Bool
    let intent: Intent

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var usesLiquidGlassLayout: Bool {
        renderingMode != .fullColor
    }

    init(
        title: String,
        systemImage: String,
        tint: Color,
        size: Size,
        iconOnly: Bool = false,
        intent: Intent
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.size = size
        self.iconOnly = iconOnly
        self.intent = intent
    }

    var body: some View {
        Group {
            if usesLiquidGlassLayout {
                if iconOnly {
                    Button(intent: intent) {
                        label
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                } else {
                    Button(intent: intent) {
                        label
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(tint)
                }
            } else {
                Button(intent: intent) {
                    label
                        .frame(maxWidth: iconOnly ? nil : .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
        }
        .controlSize(size == .small ? .small : .regular)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var label: some View {
        if iconOnly {
            Image(systemName: systemImage)
                .font(iconOnlyFont.weight(.bold))
                .frame(width: iconOnlyDimension, height: iconOnlyDimension)
        } else {
            Label(title, systemImage: systemImage)
                .font(labelFont)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var labelFont: Font {
        switch size {
        case .regular: .caption.weight(.semibold)
        case .small: .caption2.weight(.semibold)
        }
    }

    private var iconOnlyFont: Font {
        switch size {
        case .regular: .body
        case .small: .caption
        }
    }

    private var iconOnlyDimension: CGFloat {
        switch size {
        case .regular: 28
        case .small: 24
        }
    }
}

/// Opens the main app via deep link so bootstrap + `processPendingRecordingRequests` run in-app.
/// Widget `AppIntent` alone runs in the extension process and cannot start recording reliably.
private struct WidgetStartLink: View {
    enum Size {
        case regular
        case small
    }

    let title: String
    let systemImage: String
    let tint: Color
    let size: Size

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var usesLiquidGlassLayout: Bool {
        renderingMode != .fullColor
    }

    var body: some View {
        Group {
            if usesLiquidGlassLayout {
                Link(destination: TrailhoundDeepLink.startRecording) {
                    label
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(tint)
            } else {
                Link(destination: TrailhoundDeepLink.startRecording) {
                    label
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
        }
        .controlSize(size == .small ? .small : .regular)
        .accessibilityLabel(title)
    }

    private var label: some View {
        Label(title, systemImage: systemImage)
            .font(size == .regular ? .caption.weight(.semibold) : .caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

struct TrailhoundWidgetEntry: TimelineEntry {
    let date: Date
    let isRecording: Bool
    let isPaused: Bool
    let elapsed: TimeInterval
    let distanceMeters: Double
    let weekDistanceMeters: Double
    let monthDistanceMeters: Double
    let recordingStartedAt: Date?

    static func preview(
        isRecording: Bool = true,
        isPaused: Bool = false,
        elapsed: TimeInterval = 3_723,
        distanceMeters: Double = 12_400,
        weekDistanceMeters: Double = 45_200,
        monthDistanceMeters: Double = 182_000,
        recordingStartedAt: Date? = nil
    ) -> TrailhoundWidgetEntry {
        TrailhoundWidgetEntry(
            date: .now,
            isRecording: isRecording,
            isPaused: isPaused,
            elapsed: elapsed,
            distanceMeters: distanceMeters,
            weekDistanceMeters: weekDistanceMeters,
            monthDistanceMeters: monthDistanceMeters,
            recordingStartedAt: recordingStartedAt ?? (isRecording && !isPaused ? Date().addingTimeInterval(-elapsed) : nil)
        )
    }

    static func from(snapshot: RecordingControlBridge.RecordingWidgetSnapshot, at date: Date = Date()) -> TrailhoundWidgetEntry {
        TrailhoundWidgetEntry(
            date: date,
            isRecording: snapshot.isRecording,
            isPaused: snapshot.isPaused,
            elapsed: snapshot.elapsed(at: date),
            distanceMeters: snapshot.distanceMeters,
            weekDistanceMeters: snapshot.weekDistanceMeters,
            monthDistanceMeters: snapshot.monthDistanceMeters,
            recordingStartedAt: snapshot.recordingStartedAt
        )
    }
}

struct TrailhoundWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TrailhoundWidgetEntry {
        .preview(isRecording: true, isPaused: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (TrailhoundWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.preview(isRecording: true, isPaused: false))
        } else {
            completion(loadEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TrailhoundWidgetEntry>) -> Void) {
        let snapshot = RecordingControlBridge.recordingWidgetSnapshot()
        let now = Date()

        // Match Live Activity / Dynamic Island cadence (3s) so both surfaces tick together.
        if snapshot.isRecording, !snapshot.isPaused, let startedAt = snapshot.recordingStartedAt {
            let tick: TimeInterval = 3
            let horizon = 20
            var entries: [TrailhoundWidgetEntry] = []
            entries.reserveCapacity(horizon)
            for step in 0..<horizon {
                let date = now.addingTimeInterval(TimeInterval(step) * tick)
                entries.append(
                    TrailhoundWidgetEntry(
                        date: date,
                        isRecording: true,
                        isPaused: false,
                        elapsed: max(0, date.timeIntervalSince(startedAt)),
                        distanceMeters: snapshot.distanceMeters,
                        weekDistanceMeters: snapshot.weekDistanceMeters,
                        monthDistanceMeters: snapshot.monthDistanceMeters,
                        recordingStartedAt: startedAt
                    )
                )
            }
            completion(Timeline(entries: entries, policy: .atEnd))
            return
        }

        let entry = TrailhoundWidgetEntry.from(snapshot: snapshot, at: now)
        let refreshInterval: TimeInterval = snapshot.isRecording ? 15 : 30
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(refreshInterval))))
    }

    private func loadEntry() -> TrailhoundWidgetEntry {
        let snapshot = RecordingControlBridge.recordingWidgetSnapshot()
        return TrailhoundWidgetEntry.from(snapshot: snapshot)
    }
}

struct TrailhoundWidgetView: View {
    let entry: TrailhoundWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var usesLiquidGlassLayout: Bool {
        renderingMode != .fullColor
    }

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemLarge:
            largeView
        default:
            mediumView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            widgetHeader(compact: true)

            if entry.isRecording || entry.isPaused {
                Text(entry.isPaused ? WidgetL10n.paused : WidgetL10n.recording)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        usesLiquidGlassLayout
                            ? .primary
                            : (entry.isPaused ? WidgetPalette.paused : WidgetPalette.recording)
                    )
                    .lineLimit(1)
                Text(DateFormatters.formatDuration(entry.elapsed))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Text(DateFormatters.formatDistance(entry.distanceMeters))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                recordingControlsSmall
            } else {
                Text(WidgetL10n.thisWeek)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(DateFormatters.formatDistance(entry.weekDistanceMeters))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Spacer(minLength: 0)
                WidgetStartLink(
                    title: WidgetL10n.start,
                    systemImage: "play.fill",
                    tint: WidgetPalette.start,
                    size: .small
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader(compact: false)

            if entry.isRecording || entry.isPaused {
                statusBadge
                Text("\(DateFormatters.formatDuration(entry.elapsed)) · \(DateFormatters.formatDistance(entry.distanceMeters))")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                Text(WidgetL10n.thisWeek)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DateFormatters.formatDistance(entry.weekDistanceMeters))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
            recordingControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 14) {
            widgetHeader(compact: false)

            if entry.isRecording || entry.isPaused {
                statusBadge
                Text(DateFormatters.formatDuration(entry.elapsed))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(DateFormatters.formatDistance(entry.distanceMeters))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                Text(WidgetL10n.thisWeek)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(DateFormatters.formatDistance(entry.weekDistanceMeters))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(WidgetL10n.noRecording)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            recordingControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func widgetHeader(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "car.fill")
                .font(compact ? .subheadline : .headline)
                .foregroundStyle(usesLiquidGlassLayout ? .primary : WidgetPalette.brandBottom)
                .widgetAccentable(usesLiquidGlassLayout)
            Text("Trailhound")
                .font(compact ? .subheadline.weight(.semibold) : .headline.weight(.bold))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let title = entry.isPaused ? WidgetL10n.paused : WidgetL10n.recording
        if usesLiquidGlassLayout {
            Text(title)
                .font(.caption.weight(.semibold))
        } else {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.isPaused ? WidgetPalette.paused : WidgetPalette.recording)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (entry.isPaused ? WidgetPalette.paused : WidgetPalette.recording).opacity(0.14),
                    in: Capsule()
                )
        }
    }

    @ViewBuilder
    private var recordingControls: some View {
        if entry.isRecording || entry.isPaused {
            HStack(spacing: 8) {
                if entry.isPaused {
                    WidgetIntentButton(
                        title: WidgetL10n.resume,
                        systemImage: "play.fill",
                        tint: WidgetPalette.resume,
                        size: .regular,
                        intent: HomeWidgetResumeRecordingIntent()
                    )
                } else {
                    WidgetIntentButton(
                        title: WidgetL10n.pause,
                        systemImage: "pause.fill",
                        tint: WidgetPalette.paused,
                        size: .regular,
                        intent: HomeWidgetPauseRecordingIntent()
                    )
                }

                WidgetIntentButton(
                    title: WidgetL10n.stop,
                    systemImage: "stop.fill",
                    tint: WidgetPalette.stop,
                    size: .regular,
                    intent: HomeWidgetStopRecordingIntent()
                )
            }
        } else {
            WidgetStartLink(
                title: WidgetL10n.start,
                systemImage: "play.fill",
                tint: WidgetPalette.start,
                size: .regular
            )
        }
    }

    @ViewBuilder
    private var recordingControlsSmall: some View {
        HStack(spacing: 6) {
            if entry.isPaused {
                WidgetIntentButton(
                    title: WidgetL10n.resume,
                    systemImage: "play.fill",
                    tint: WidgetPalette.resume,
                    size: .small,
                    intent: HomeWidgetResumeRecordingIntent()
                )
            } else {
                WidgetIntentButton(
                    title: WidgetL10n.pause,
                    systemImage: "pause.fill",
                    tint: WidgetPalette.paused,
                    size: .small,
                    intent: HomeWidgetPauseRecordingIntent()
                )
            }

            WidgetIntentButton(
                title: WidgetL10n.stop,
                systemImage: "stop.fill",
                tint: WidgetPalette.stop,
                size: .small,
                intent: HomeWidgetStopRecordingIntent()
            )
        }
    }
}

struct TrailhoundWidget: Widget {
    let kind = "TrailhoundWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TrailhoundWidgetProvider()) { entry in
            TrailhoundWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetAdaptiveBackground()
                }
        }
        .configurationDisplayName(WidgetL10n.displayName)
        .description(WidgetL10n.description)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct LiveActivityCarIcon: View {
    var side: CGFloat = 22
    var photoRevision: String? = nil
    /// Island chrome is black — white symbols read cleaner than brand blue.
    var symbolTint: Color = .white

    var body: some View {
        markContent
            .frame(width: side, height: side)
    }

    @ViewBuilder
    private var markContent: some View {
        // Photo wins when App Group carries a usable thumb for this revision; otherwise fixed
        // right-facing `car.side.fill`.
        if let image = LiveActivityVehicleMarkStore.image(revision: photoRevision) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "car.side.fill")
                .font(.system(size: side * 0.58, weight: .semibold))
                .foregroundStyle(symbolTint)
                .scaleEffect(x: -1, y: 1)
        }
    }
}

/// Compact circular control — tinted disc only; no outer plate / glass box.
///
/// Uses `.borderedProminent` rather than a hand-drawn `Circle()` behind `.plain`: WidgetKit only
/// draws its built-in press highlight for system button styles, and without that highlight the
/// round trip through the intent reads as lag even when it is fast.
private struct LiveActivityIslandButton<Intent: AppIntent>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let intent: Intent
    var size: CGFloat = 36

    var body: some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .controlSize(.mini)
        .tint(tint)
        .frame(width: size, height: size)
        .accessibilityLabel(title)
    }
}

/// Stable pause/play slot — CSS-style bounce-in / bounce-out glyph swap on tap.
///
/// Live Activity state arrives late from ActivityKit; `@State displayPaused` flips on tap so the
/// bounce runs immediately instead of waiting for the next ContentState push.
private struct LiveActivityPlaybackControl: View {
    let isPaused: Bool
    var size: CGFloat = 38

    @State private var displayPaused: Bool

    init(isPaused: Bool, size: CGFloat = 38) {
        self.isPaused = isPaused
        self.size = size
        _displayPaused = State(initialValue: isPaused)
    }

    var body: some View {
        Button(intent: WidgetTogglePauseResumeIntent(wasPaused: displayPaused)) {
            ZStack {
                LiveActivityBounceGlyph(
                    systemName: "pause.fill",
                    isActive: !displayPaused,
                    size: size
                )
                LiveActivityBounceGlyph(
                    systemName: "play.fill",
                    isActive: displayPaused,
                    size: size,
                    offsetX: 0.8
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .controlSize(.mini)
        .tint(displayPaused ? WidgetPalette.resume : WidgetPalette.paused)
        .frame(width: size, height: size)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: displayPaused) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            CubicKeyframe(0.82, duration: 0.0004)
            CubicKeyframe(1.10, duration: 0.0006)
            CubicKeyframe(1.0, duration: 0.0005)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                displayPaused.toggle()
            }
        )
        .onChange(of: isPaused) { _, newValue in
            displayPaused = newValue
        }
        .accessibilityLabel(displayPaused ? WidgetL10n.resume : WidgetL10n.pause)
    }
}

private struct LiveActivityBounceGlyph: View {
    let systemName: String
    let isActive: Bool
    let size: CGFloat
    var offsetX: CGFloat = 0

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(.white)
            .offset(x: offsetX)
            .keyframeAnimator(
                initialValue: isActive ? 1.0 : 0.2,
                trigger: isActive
            ) { view, scale in
                view
                    .scaleEffect(scale)
                    .opacity(scale > 0.18 ? 1 : 0)
            } keyframes: { _ in
                if isActive {
                    LinearKeyframe(0.2, duration: 0)
                    CubicKeyframe(1.22, duration: 0.0008)
                    CubicKeyframe(0.94, duration: 0.0005)
                    CubicKeyframe(1.0, duration: 0.0004)
                } else {
                    LinearKeyframe(1.0, duration: 0)
                    CubicKeyframe(1.08, duration: 0.0003)
                    CubicKeyframe(0.2, duration: 0.0009)
                }
            }
    }
}

/// Distance / Speed row for expanded Island (mockup hierarchy).
/// `fixedSize` keeps labels and values whole — the Island must never truncate them.
private struct LiveActivityIslandMetricRow: View {
    let systemImage: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.10)))

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            // The trailing Island region is narrow — scale down instead of truncating.
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
    }
}

/// Lock Screen / StandBy banner — pause/stop controls stay interactive here.
private struct LiveActivityLockScreenBanner: View {
    let state: TripRecordingAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LiveActivityCarIcon(
                side: 54,
                photoRevision: state.vehiclePhotoRevision,
                symbolTint: WidgetPalette.brandBottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(DateFormatters.formatDuration(TimeInterval(state.elapsedSeconds)))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(state.isPaused ? WidgetPalette.paused : WidgetPalette.recording)
                        .frame(width: 6, height: 6)
                    Text(state.isPaused ? WidgetL10n.paused : WidgetL10n.recording)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(state.isPaused ? WidgetPalette.paused : .secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                Text(liveActivityBannerMeta(state))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                LiveActivityPlaybackControl(isPaused: state.isPaused, size: 40)
                LiveActivityIslandButton(
                    title: WidgetL10n.stop,
                    systemImage: "stop.fill",
                    tint: WidgetPalette.stop,
                    intent: WidgetStopRecordingIntent(),
                    size: 40
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func liveActivityBannerMeta(_ state: TripRecordingAttributes.ContentState) -> String {
        let distance = DateFormatters.formatDistance(state.distanceMeters)
        if state.isPaused {
            return distance
        }
        return "\(distance) · \(state.currentSpeedKmh) km/s"
    }
}

/// CarPlay Dashboard + watchOS Smart Stack — glanceable, non-interactive (CarPlay strips buttons).
private struct LiveActivitySmallFamilyBanner: View {
    let state: TripRecordingAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            iconColumn
            metricColumn(
                value: DateFormatters.formatDuration(TimeInterval(state.elapsedSeconds)),
                label: WidgetL10n.duration
            )
            metricColumn(
                value: DateFormatters.formatDistance(state.distanceMeters),
                label: WidgetL10n.distance
            )
            metricColumn(
                value: state.isPaused ? "—" : "\(state.currentSpeedKmh) km/s",
                label: WidgetL10n.speed
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var iconColumn: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            LiveActivityCarIcon(
                side: side,
                photoRevision: state.vehiclePhotoRevision,
                symbolTint: WidgetPalette.brandBottom
            )
            .frame(width: side, height: side)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    private func metricColumn(value: String, label: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Picks Lock Screen (medium) vs CarPlay / Smart Stack (small) layouts.
@available(iOS 18.0, *)
private struct LiveActivityBannerRoot: View {
    @Environment(\.activityFamily) private var activityFamily
    let state: TripRecordingAttributes.ContentState

    var body: some View {
        Group {
            switch activityFamily {
            case .small:
                LiveActivitySmallFamilyBanner(state: state)
            case .medium:
                LiveActivityLockScreenBanner(state: state)
            @unknown default:
                LiveActivityLockScreenBanner(state: state)
            }
        }
        .activityBackgroundTint(
            (state.isPaused ? WidgetPalette.paused : WidgetPalette.brandBottom).opacity(0.10)
        )
    }
}

/// Live Activity for Lock Screen, Dynamic Island, and CarPlay Dashboard.
///
/// Requires iOS 18 so we can declare `activityFamily.small` (CarPlay 4-column tile).
/// Home Screen / Lock Screen widgets still load on iOS 17 via the other widgets in this bundle.
@available(iOS 18.0, *)
struct TrailhoundLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripRecordingAttributes.self) { context in
            LiveActivityBannerRoot(state: context.state)
        } dynamicIsland: { context in
            liveActivityDynamicIsland(context: context)
        }
        .supplementalActivityFamilies([.small])
    }
}

@MainActor
private func liveActivityDynamicIsland(
    context: ActivityViewContext<TripRecordingAttributes>
) -> DynamicIsland {
    DynamicIsland {
        // Vehicle mark + duration share one row height; status copy lives in `.bottom`.
        DynamicIslandExpandedRegion(.leading) {
            let markSide: CGFloat = 40
            HStack(alignment: .center, spacing: 10) {
                LiveActivityCarIcon(
                    side: markSide,
                    photoRevision: context.state.vehiclePhotoRevision,
                    symbolTint: .white
                )

                Text(DateFormatters.formatDuration(TimeInterval(context.state.elapsedSeconds)))
                    .font(.system(size: markSide * 0.92, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(height: markSide)
        }

        DynamicIslandExpandedRegion(.trailing) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 6) {
                    LiveActivityIslandMetricRow(
                        systemImage: "road.lanes",
                        label: WidgetL10n.distance,
                        value: DateFormatters.formatDistance(context.state.distanceMeters)
                    )
                    LiveActivityIslandMetricRow(
                        systemImage: "gauge.with.dots.needle.67percent",
                        label: WidgetL10n.speed,
                        value: context.state.isPaused
                            ? "—"
                            : "\(context.state.currentSpeedKmh) km/s"
                    )
                }
            }
        }

        DynamicIslandExpandedRegion(.bottom) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                    Circle()
                        .fill(context.state.isPaused ? WidgetPalette.paused : Color.green)
                        .frame(width: 6, height: 6)
                    Text(context.state.isPaused ? WidgetL10n.tripPaused : WidgetL10n.tripActive)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    LiveActivityPlaybackControl(isPaused: context.state.isPaused, size: 36)
                    LiveActivityIslandButton(
                        title: WidgetL10n.stop,
                        systemImage: "stop.fill",
                        tint: WidgetPalette.stop,
                        intent: WidgetStopRecordingIntent(),
                        size: 36
                    )
                }
            }
            .padding(.top, 2)
        }
    } compactLeading: {
        LiveActivityCarIcon(
            side: 18,
            photoRevision: context.state.vehiclePhotoRevision,
            symbolTint: .white
        )
    } compactTrailing: {
        Text(DateFormatters.formatDuration(TimeInterval(context.state.elapsedSeconds)))
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
    } minimal: {
        LiveActivityCarIcon(
            side: 15,
            photoRevision: context.state.vehiclePhotoRevision,
            symbolTint: .white
        )
    }
    .keylineTint(context.state.isPaused ? WidgetPalette.paused : WidgetPalette.brandBottom)
}

@main
struct TrailhoundWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrailhoundWidget()
        TrailhoundLockScreenWidget()
        if #available(iOS 18.0, *) {
            TrailhoundLiveActivity()
        }
    }
}

#Preview(as: .systemSmall) {
    TrailhoundWidget()
} timeline: {
    TrailhoundWidgetEntry.preview(isRecording: true, isPaused: false)
    TrailhoundWidgetEntry.preview(isRecording: true, isPaused: true)
    TrailhoundWidgetEntry.preview(isRecording: false, isPaused: false)
}

#Preview(as: .systemMedium) {
    TrailhoundWidget()
} timeline: {
    TrailhoundWidgetEntry.preview(isRecording: true, isPaused: false)
    TrailhoundWidgetEntry.preview(isRecording: false, isPaused: false)
}

#Preview(as: .systemLarge) {
    TrailhoundWidget()
} timeline: {
    TrailhoundWidgetEntry.preview(isRecording: true, isPaused: false)
    TrailhoundWidgetEntry.preview(isRecording: false, isPaused: false)
}
