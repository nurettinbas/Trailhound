import ActivityKit
import AppIntents
import SwiftUI
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

    static func preview(
        isRecording: Bool = true,
        isPaused: Bool = false,
        elapsed: TimeInterval = 3_723,
        distanceMeters: Double = 12_400,
        weekDistanceMeters: Double = 45_200,
        monthDistanceMeters: Double = 182_000
    ) -> TrailhoundWidgetEntry {
        TrailhoundWidgetEntry(
            date: .now,
            isRecording: isRecording,
            isPaused: isPaused,
            elapsed: elapsed,
            distanceMeters: distanceMeters,
            weekDistanceMeters: weekDistanceMeters,
            monthDistanceMeters: monthDistanceMeters
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
        let entry = loadEntry()
        let refreshInterval: TimeInterval = entry.isRecording ? 15 : 30
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(refreshInterval)))
        completion(timeline)
    }

    private func loadEntry() -> TrailhoundWidgetEntry {
        let defaults = UserDefaults(suiteName: "group.com.trailhound.app")
        return TrailhoundWidgetEntry(
            date: Date(),
            isRecording: defaults?.bool(forKey: "recording.isActive") ?? false,
            isPaused: defaults?.bool(forKey: "recording.isPaused") ?? false,
            elapsed: defaults?.double(forKey: "recording.elapsed") ?? 0,
            distanceMeters: defaults?.double(forKey: "recording.distance") ?? 0,
            weekDistanceMeters: defaults?.double(forKey: "stats.weekDistance") ?? 0,
            monthDistanceMeters: defaults?.double(forKey: "stats.monthDistance") ?? 0
        )
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
                .font(compact ? .subheadline.weight(.semibold) : .headline)
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
                        intent: WidgetResumeRecordingIntent()
                    )
                } else {
                    WidgetIntentButton(
                        title: WidgetL10n.pause,
                        systemImage: "pause.fill",
                        tint: WidgetPalette.paused,
                        size: .regular,
                        intent: WidgetPauseRecordingIntent()
                    )
                }

                WidgetIntentButton(
                    title: WidgetL10n.stop,
                    systemImage: "stop.fill",
                    tint: WidgetPalette.stop,
                    size: .regular,
                    intent: WidgetStopRecordingIntent()
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
                    intent: WidgetResumeRecordingIntent()
                )
            } else {
                WidgetIntentButton(
                    title: WidgetL10n.pause,
                    systemImage: "pause.fill",
                    tint: WidgetPalette.paused,
                    size: .small,
                    intent: WidgetPauseRecordingIntent()
                )
            }

            WidgetIntentButton(
                title: WidgetL10n.stop,
                systemImage: "stop.fill",
                tint: WidgetPalette.stop,
                size: .small,
                intent: WidgetStopRecordingIntent()
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
    let isPaused: Bool
    var font: Font = .title2

    var body: some View {
        Group {
            if isPaused {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "car.side.fill")
                    .foregroundStyle(.blue)
                    .scaleEffect(x: -1, y: 1)
            }
        }
        .font(font)
    }
}

/// Compact circular control for the expanded Dynamic Island — avoids bulky bordered buttons.
private struct LiveActivityIslandButton<Intent: AppIntent>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let intent: Intent

    var body: some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint.gradient, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct TrailhoundLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripRecordingAttributes.self) { context in
            HStack(spacing: 12) {
                LiveActivityCarIcon(isPaused: context.state.isPaused)

                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.isPaused ? WidgetL10n.paused : WidgetL10n.recording)
                        .font(.headline)
                        .foregroundStyle(context.state.isPaused ? .orange : .primary)
                    Text(liveActivityStats(context.state))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                liveActivityControls(isPaused: context.state.isPaused)
            }
            .padding()
            .activityBackgroundTint((context.state.isPaused ? Color.orange : Color.blue).opacity(0.12))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityCarIcon(isPaused: context.state.isPaused, font: .title3)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.isPaused ? WidgetL10n.paused : WidgetL10n.recording)
                            .font(.caption)
                            .foregroundStyle(context.state.isPaused ? .orange : .primary)
                        Text(DateFormatters.formatDuration(TimeInterval(context.state.elapsedSeconds)))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(liveActivityIslandSecondaryStats(context.state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        liveActivityIslandControls(isPaused: context.state.isPaused)
                    }
                }
            } compactLeading: {
                LiveActivityCarIcon(isPaused: context.state.isPaused, font: .caption)
            } compactTrailing: {
                Text(DateFormatters.formatDuration(TimeInterval(context.state.elapsedSeconds)))
                    .font(.caption2)
                    .monospacedDigit()
            } minimal: {
                LiveActivityCarIcon(isPaused: context.state.isPaused, font: .caption2)
            }
        }
    }

    @ViewBuilder
    private func liveActivityControls(isPaused: Bool) -> some View {
        HStack(spacing: 8) {
            if isPaused {
                WidgetIntentButton(
                    title: WidgetL10n.resume,
                    systemImage: "play.fill",
                    tint: WidgetPalette.resume,
                    size: .small,
                    iconOnly: true,
                    intent: WidgetResumeRecordingIntent()
                )
            } else {
                WidgetIntentButton(
                    title: WidgetL10n.pause,
                    systemImage: "pause.fill",
                    tint: WidgetPalette.paused,
                    size: .small,
                    iconOnly: true,
                    intent: WidgetPauseRecordingIntent()
                )
            }

            WidgetIntentButton(
                title: WidgetL10n.stop,
                systemImage: "stop.fill",
                tint: WidgetPalette.stop,
                size: .small,
                iconOnly: true,
                intent: WidgetStopRecordingIntent()
            )
        }
    }

    @ViewBuilder
    private func liveActivityIslandControls(isPaused: Bool) -> some View {
        HStack(spacing: 10) {
            if isPaused {
                LiveActivityIslandButton(
                    title: WidgetL10n.resume,
                    systemImage: "play.fill",
                    tint: WidgetPalette.resume,
                    intent: WidgetResumeRecordingIntent()
                )
            } else {
                LiveActivityIslandButton(
                    title: WidgetL10n.pause,
                    systemImage: "pause.fill",
                    tint: WidgetPalette.paused,
                    intent: WidgetPauseRecordingIntent()
                )
            }

            LiveActivityIslandButton(
                title: WidgetL10n.stop,
                systemImage: "stop.fill",
                tint: WidgetPalette.stop,
                intent: WidgetStopRecordingIntent()
            )
        }
    }

    private func liveActivityIslandSecondaryStats(_ state: TripRecordingAttributes.ContentState) -> String {
        let distance = DateFormatters.formatDistance(state.distanceMeters)
        if state.isPaused {
            return distance
        }
        return "\(distance) · \(state.currentSpeedKmh) km/s"
    }

    private func liveActivityStats(_ state: TripRecordingAttributes.ContentState) -> String {
        if state.isPaused {
            return "\(DateFormatters.formatDuration(TimeInterval(state.elapsedSeconds))) · \(DateFormatters.formatDistance(state.distanceMeters))"
        }
        return "\(DateFormatters.formatDuration(TimeInterval(state.elapsedSeconds))) · \(DateFormatters.formatDistance(state.distanceMeters)) · \(state.currentSpeedKmh) km/s"
    }
}

@main
struct TrailhoundWidgetBundle: WidgetBundle {
    var body: some Widget {
        TrailhoundWidget()
        TrailhoundLockScreenWidget()
        TrailhoundLiveActivity()
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
