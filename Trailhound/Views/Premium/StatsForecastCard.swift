import Charts
import SwiftUI
import UIKit

struct StatsForecastCard: View {
    let forecast: MonthCostForecast
    let currencyCode: String
    var isExpanded: Bool = false
    var onOpen: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsTrend = false

    private var usesOverlay: Bool {
        forecast.hasData && !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                Group {
                    if usesOverlay {
                        overlayPoster
                    } else {
                        stackedContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.trailhoundCardPress)
            .allowsHitTesting(!isExpanded)
            Button(action: onOpen) {
                GlassToolbarSymbol(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            .allowsHitTesting(!isExpanded)
            .padding(.top, StatsCardTokens.posterOverlayInsets.top)
            .padding(.trailing, StatsCardTokens.posterOverlayInsets.trailing)
        }
        .glassEntranceGlint(
            cornerRadius: StatsCardTokens.radius,
            id: "stats.forecast.ready",
            isEnabled: forecast.hasData
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("stats.premium.forecast")
        .accessibilityLabel(L10n.string("premium.forecast.title"))
        .accessibilityValue(accessibilityValue)
        .onAppear(perform: revealTrend)
        .onChange(of: forecast.trendRatio) { _, _ in
            revealTrend()
        }
    }

    private var overlayPoster: some View {
        StatsForecastHeroPoster(
            forecast: forecast,
            currencyCode: currencyCode,
            height: StatsCardTokens.posterHeight,
            reservesExpandSlot: true,
            showsComposition: true,
            showsTrend: showsTrend
        )
    }

    private var stackedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            overlayCopy
            if !forecast.hasData {
                Text(L10n.string("premium.forecast.subtitle"))
                    .font(.caption)
                    .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
            }
        }
        .padding(StatsCardTokens.contentInset)
    }

    private var overlayCopy: some View {
        StatsForecastHeroCopy(
            forecast: forecast,
            currencyCode: currencyCode,
            reservesExpandSlot: false,
            showsComposition: true,
            showsTrend: showsTrend
        )
    }

    private var accessibilityValue: String {
        var parts = [FuelCostCalculator.formatCost(forecast.projectedTotal, currencyCode: currencyCode)]
        if let ratio = forecast.trendRatio {
            parts.append(StatsForecastCopy.trend(ratio))
        }
        parts.append(StatsForecastCopy.confidence(forecast.confidence))
        return parts.joined(separator: ", ")
    }

    private var playsMotion: Bool {
        !reduceMotion && !UITestSupport.isEnabled
    }

    private func revealTrend() {
        guard forecast.trendRatio != nil else {
            showsTrend = false
            return
        }
        guard !showsTrend else { return }
        guard playsMotion else {
            showsTrend = true
            return
        }
        withAnimation(TrailhoundMotion.pinPop.delay(0.08)) {
            showsTrend = true
        }
    }
}

enum StatsForecastCopy {
    static func confidence(_ confidence: MonthCostForecastConfidence) -> String {
        switch confidence {
        case .low: L10n.string("premium.forecast.confidence.low")
        case .medium: L10n.string("premium.forecast.confidence.medium")
        case .high: L10n.string("premium.forecast.confidence.high")
        }
    }

    static func trend(_ ratio: Double) -> String {
        let percent = Int((abs(ratio) * 100).rounded())
        let format = ratio >= 0
            ? L10n.string("premium.forecast.trend.up")
            : L10n.string("premium.forecast.trend.down")
        return String(format: format, percent)
    }
}

struct StatsForecastHeroCopy: View {
    let forecast: MonthCostForecast
    let currencyCode: String
    var reservesExpandSlot: Bool
    var showsComposition: Bool
    var showsTrend: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("premium.forecast.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                .statsFrostChip()
                .padding(.trailing, reservesExpandSlot ? 44 : 0)
            Text(FuelCostCalculator.formatCost(forecast.projectedTotal, currencyCode: currencyCode))
                .font(.title.weight(.bold).monospacedDigit())
                .glassAccentForeground()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .numericTextAnimation(value: forecast.projectedTotal)
            if forecast.hasData {
                metricsLine
            }
            if showsComposition, forecast.hasComposition {
                StatsSegmentBar(segments: ForecastCompositionBlock.segments(for: forecast))
            }
        }
    }

    private var metricsLine: some View {
        HStack(spacing: 6) {
            if let ratio = forecast.trendRatio, showsTrend {
                Image(systemName: ratio >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        ratio >= 0
                            ? GlassSemantic.paused(for: colorScheme)
                            : GlassSemantic.success(for: colorScheme)
                    )
                Text(StatsForecastCopy.trend(ratio))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                    .transition(reduceMotion ? .opacity : TrailhoundMotion.softScaleInTransition)
                Text("·")
                    .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
            }
            Text(StatsForecastCopy.confidence(forecast.confidence))
                .font(.caption)
                .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

struct StatsForecastHeroPoster: View {
    let forecast: MonthCostForecast
    let currencyCode: String
    var height: CGFloat
    var reservesExpandSlot: Bool
    var showsComposition: Bool
    var showsTrend: Bool
    var cornerRadius: CGFloat = StatsCardTokens.radius

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            sparkline
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            LinearGradient(
                colors: [
                    shellPalette.atmosphere(for: colorScheme).bottom.color.opacity(0.92),
                    shellPalette.atmosphere(for: colorScheme).bottom.color.opacity(0)
                ],
                startPoint: .bottom,
                endPoint: .center
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            StatsForecastHeroCopy(
                forecast: forecast,
                currencyCode: currencyCode,
                reservesExpandSlot: reservesExpandSlot,
                showsComposition: showsComposition,
                showsTrend: showsTrend
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .statsPosterOverlayPadding()
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var sparkline: some View {
        Color.clear
            .overlay {
                if !forecast.monthlyTotals.isEmpty {
                    Chart(forecast.monthlyTotals) { month in
                        AreaMark(
                            x: .value("m", month.monthStart, unit: .month),
                            y: .value("c", month.total)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    shellPalette.tintColor(for: colorScheme).opacity(0.55),
                                    shellPalette.tintColor(for: colorScheme).opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("m", month.monthStart, unit: .month),
                            y: .value("c", month.total)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        PointMark(
                            x: .value("m", month.monthStart, unit: .month),
                            y: .value("c", month.total)
                        )
                        .symbolSize(isCurrentMonth(month.monthStart) ? 36 : 0)
                        .foregroundStyle(Color.white)
                    }
                    .chartStatsSparklineFill()
                }
            }
            .accessibilityHidden(true)
    }

    private func isCurrentMonth(_ monthStart: Date) -> Bool {
        Calendar.current.isDate(monthStart, equalTo: forecast.monthStart, toGranularity: .month)
    }
}

struct StatsForecastCardGlobalFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

struct StatsForecastExpandOverlay: View {
    let forecast: MonthCostForecast
    let currencyCode: String
    let sourceGlobal: CGRect
    @Binding var isExpanded: Bool
    var onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let overlayGlobal = proxy.frame(in: .global)
            let frame = AchievementGalleryExpandLayout.localSurface(
                sourceGlobal: sourceGlobal,
                overlayGlobal: overlayGlobal,
                expanded: isExpanded
            )
            let radius = AchievementGalleryExpandLayout.cornerRadius(expanded: isExpanded)
            let window = windowSafeInsets
            let topInset = max(proxy.safeAreaInsets.top, window.top, 54)
            let bottomInset = max(proxy.safeAreaInsets.bottom, window.bottom, 34)
            ZStack {
                Color.clear
                    .allowsHitTesting(false)
                surface(radius: radius, topInset: topInset, bottomInset: bottomInset)
                    .frame(width: frame.width, height: frame.height, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .position(x: frame.midX, y: frame.midY)
            }
            .animation(TrailhoundMotion.badgeCardExpand(reduceMotion: reduceMotion), value: isExpanded)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("stats.premium.forecast.expanded")
    }

    private var windowSafeInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let inset = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets {
            return inset
        }
        return scenes.flatMap(\.windows).first?.safeAreaInsets
            ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    @ViewBuilder
    private func surface(radius: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            StatsForecastCard(
                forecast: forecast,
                currencyCode: currencyCode,
                isExpanded: true,
                onOpen: {}
            )
            .opacity(isExpanded ? 0 : 1)
            .allowsHitTesting(false)
            StatsForecastDetailSheet(
                forecast: forecast,
                currencyCode: currencyCode,
                onClose: onClose,
                topInset: topInset,
                bottomInset: bottomInset
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isExpanded ? 1 : 0)
            .allowsHitTesting(isExpanded)
        }
        .background {
            AtmosphericBackground()
                .allowsHitTesting(false)
        }
        .glassCard(cornerRadius: radius, contentInset: 0, frozen: true, allowsNative: false)
    }
}

struct StatsForecastDetailSheet: View {
    let forecast: MonthCostForecast
    let currencyCode: String
    var onClose: () -> Void
    var topInset: CGFloat = 54
    var bottomInset: CGFloat = 34

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(L10n.string("premium.forecast.detail.title"))
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    GlassNavCircleIcon(systemName: "arrow.down.right.and.arrow.up.left")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.mapExitFullscreen)
                .accessibilityIdentifier("stats.premium.forecast.expanded.close")
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.top, topInset)
            .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StatsForecastHeroPoster(
                        forecast: forecast,
                        currencyCode: currencyCode,
                        height: StatsCardTokens.posterExpandedHeight,
                        reservesExpandSlot: false,
                        showsComposition: false,
                        showsTrend: true,
                        cornerRadius: StatsCardTokens.nestedRadius
                    )
                    if forecast.hasComposition {
                        compositionPanel
                    }
                    breakdownPanel
                }
                .padding(16)
                .padding(.bottom, bottomInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGlassShell()
    }

    private var compositionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatsSegmentBar(segments: ForecastCompositionBlock.segments(for: forecast))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(legendRows, id: \.id) { row in
                    HStack(spacing: 8) {
                        StatsSegmentSwatch(index: row.index)
                        Text(ForecastCompositionBlock.title(for: row.id))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .statsNestedPanel()
    }

    private var legendRows: [(id: String, index: Int)] {
        ForecastCompositionBlock.segments(for: forecast).enumerated().compactMap { index, segment in
            segment.share > 0 ? (id: segment.id, index: index) : nil
        }
    }

    private var breakdownPanel: some View {
        VStack(spacing: 10) {
            detailRow(L10n.string("premium.forecast.row.drive"), forecast.projectedFuel)
            detailRow(L10n.string("premium.forecast.row.installments"), forecast.installmentsDue)
            detailRow(L10n.string("premium.forecast.row.other"), forecast.otherExpenses)
            detailRow(L10n.string("premium.forecast.row.logged_fuel"), forecast.loggedFuel)
        }
    }

    private func detailRow(_ title: String, _ amount: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
            Spacer(minLength: 8)
            Text(amount > 0 ? FuelCostCalculator.formatCost(amount, currencyCode: currencyCode) : "—")
                .font(.body.weight(.semibold).monospacedDigit())
                .glassAccentForeground()
                .opacity(amount > 0 ? 1 : 0.55)
        }
        .statsNestedPanel()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(
            amount > 0 ? FuelCostCalculator.formatCost(amount, currencyCode: currencyCode) : "—"
        )
    }
}

enum ForecastCompositionBlock {
    static func segments(for forecast: MonthCostForecast) -> [StatsSegment] {
        let shares = forecast.compositionShares
        let opacities = StatsSegmentTokens.opacities
        return [
            StatsSegment(id: "drive", share: shares.drive, opacity: opacities[0]),
            StatsSegment(id: "installments", share: shares.installments, opacity: opacities[1]),
            StatsSegment(id: "other", share: shares.other, opacity: opacities[2])
        ]
    }

    static func title(for segmentID: String) -> String {
        switch segmentID {
        case "drive": L10n.string("premium.forecast.row.drive")
        case "installments": L10n.string("premium.forecast.row.installments")
        case "other": L10n.string("premium.forecast.row.other")
        default: segmentID
        }
    }
}
