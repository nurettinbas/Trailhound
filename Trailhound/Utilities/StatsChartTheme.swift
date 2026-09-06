import Charts
import SwiftUI

/// Shared palette and styling for Stats tab charts.
enum StatsChartTheme {
    // MARK: - Daily bar gradients

    static let distanceBarFill = TrailhoundBrandColors.brandBottom.gradient

    static let durationBarFill = LinearGradient(
        colors: [
            Color(red: 0.96, green: 0.62, blue: 0.22),
            Color(red: 0.72, green: 0.48, blue: 0.95)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let averageSpeedBarFill = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.58, blue: 0.24),
            Color(red: 0.92, green: 0.76, blue: 0.28)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let maxSpeedBarFill = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.40, blue: 0.52),
            Color(red: 0.98, green: 0.58, blue: 0.24)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cruiseSpeedBarFill = LinearGradient(
        colors: [
            Color(red: 0.28, green: 0.78, blue: 0.86),
            Color(red: 0.34, green: 0.82, blue: 0.58)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let mostCommonSpeedBarFill = LinearGradient(
        colors: [
            Color(red: 0.45, green: 0.58, blue: 0.98),
            Color(red: 0.62, green: 0.42, blue: 0.95)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let stopDurationBarFill = LinearGradient(
        colors: [
            Color(red: 0.72, green: 0.48, blue: 0.95),
            Color(red: 0.58, green: 0.64, blue: 0.92)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let fuelCostBarFill = LinearGradient(
        colors: [
            Color(red: 0.34, green: 0.82, blue: 0.58),
            Color(red: 0.28, green: 0.78, blue: 0.86)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let dynamicFuelCostBarFill = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.58, blue: 0.24),
            Color(red: 0.95, green: 0.40, blue: 0.52)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Donut slice palettes

    private static let distanceSliceColors: [Color] = [
        TrailhoundBrandColors.brandBottom,
        Color(red: 0.34, green: 0.82, blue: 0.58),
        Color(red: 0.98, green: 0.58, blue: 0.24),
        Color(red: 0.72, green: 0.48, blue: 0.95),
        Color(red: 0.95, green: 0.40, blue: 0.52),
        Color(red: 0.28, green: 0.78, blue: 0.86),
        Color(red: 0.92, green: 0.76, blue: 0.28),
        Color(red: 0.58, green: 0.64, blue: 0.92)
    ]

    private static let durationSliceColors: [Color] = [
        TrailhoundBrandColors.brandTop,
        Color(red: 0.48, green: 0.90, blue: 0.72),
        Color(red: 1.0, green: 0.72, blue: 0.42),
        Color(red: 0.82, green: 0.62, blue: 1.0),
        Color(red: 1.0, green: 0.55, blue: 0.68),
        Color(red: 0.45, green: 0.88, blue: 0.94),
        Color(red: 1.0, green: 0.88, blue: 0.45),
        Color(red: 0.70, green: 0.76, blue: 1.0)
    ]

    static func sliceColor(
        forStableKey key: String,
        durationStyle: Bool,
        domainKeys: [String]
    ) -> Color {
        let palette = durationStyle ? durationSliceColors : distanceSliceColors
        let ordered = Array(Set(domainKeys)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard let index = ordered.firstIndex(of: key) else {
            return palette[stableHash(key) % palette.count]
        }
        return palette[index % palette.count]
    }

    static func sliceScale(
        labels: [String],
        stableKeys: [String],
        durationStyle: Bool
    ) -> ([String], [Color]) {
        let keys = stableKeys.isEmpty ? labels : stableKeys
        let colors = zip(labels, keys).map { _, key in
            sliceColor(forStableKey: key, durationStyle: durationStyle, domainKeys: keys)
        }
        return (labels, colors)
    }

    // MARK: - Cost bucket colors

    static func bucketColor(for bucket: VehicleCostBucket) -> Color {
        switch bucket {
        case .fuel: Color(red: 0.27, green: 0.82, blue: 0.63)
        case .service: Color(red: 0.96, green: 0.65, blue: 0.14)
        case .insurance: Color(red: 0.61, green: 0.50, blue: 0.91)
        case .casco: TrailhoundBrandColors.brandBottom
        case .other: Color.secondary.opacity(0.55)
        }
    }

    static var bucketDomain: [String] {
        VehicleCostBucket.allCases.map(\.displayName)
    }

    static var bucketRange: [Color] {
        VehicleCostBucket.allCases.map(bucketColor(for:))
    }

    static func categoryColor(for category: VehicleExpenseCategory) -> Color {
        switch category {
        case .fuel: bucketColor(for: .fuel)
        case .service: bucketColor(for: .service)
        case .repair: Color(red: 0.98, green: 0.48, blue: 0.32)
        case .trafficInsurance: bucketColor(for: .insurance)
        case .casco: bucketColor(for: .casco)
        case .inspection: Color(red: 0.45, green: 0.72, blue: 0.98)
        case .accessory: Color(red: 0.88, green: 0.52, blue: 0.92)
        case .other: bucketColor(for: .other)
        }
    }

    static let tripEstimateColor = Color(red: 0.28, green: 0.78, blue: 0.86)

    // MARK: - Layout tokens

    static let barCornerRadius: CGFloat = 5
    static let donutInnerRadius: CGFloat = 0.58
    static let donutAngularInset: CGFloat = 2
    static let legendColumns: Int = 4
    static let legendDotSize: CGFloat = 8
    static let legendCellSpacing: CGFloat = 8
    static let legendRowSpacing: CGFloat = 8
    /// Breathing room between donut plot and legend grid.
    static let donutLegendTopPadding: CGFloat = 14
    /// Inset inside the Swift Charts plot area.
    static let plotHorizontalInset: CGFloat = 16
    static let plotVerticalInset: CGFloat = 8
    /// Padding between chart view and card rim.
    static let chartCardHorizontalPadding: CGFloat = 6

    /// Cost timeline plot matches trip daily bar height.
    static let costBarPlotHeight: CGFloat = 200
    /// Compact category legend under the cost plot (dot + label row).
    static let costBarLegendHeight: CGFloat = 40
    /// Plot + legend spacing + legend reserve for deferred skeleton / pager.
    static let costBarChartBodyHeight: CGFloat = costBarPlotHeight + legendRowSpacing + costBarLegendHeight

    /// Swift Charts linear/temporal X scales require at least two distinct domain values.
    /// Sparse series (1–3 points) get equal side padding so bars sit centered in the card.
    static func xScaleDomain(from dates: [Date], padding component: Calendar.Component) -> [Date] {
        guard let lower = dates.min(), let upper = dates.max() else { return [] }
        let calendar = Calendar.current
        if dates.count <= 3 {
            let paddedLower = calendar.date(byAdding: component, value: -1, to: lower) ?? lower
            let paddedUpper = calendar.date(byAdding: component, value: 1, to: upper) ?? upper
            if paddedLower != paddedUpper { return [paddedLower, paddedUpper] }
        }
        if lower != upper { return [lower, upper] }
        let paddedUpper = calendar.date(byAdding: component, value: 1, to: lower)
            ?? lower.addingTimeInterval(component == .month ? 2_592_000 : 86_400)
        return [lower, paddedUpper]
    }

    static func xScaleDomain(lower: Double, upper: Double) -> [Double] {
        guard lower.isFinite, upper.isFinite else { return [0, 1] }
        if lower != upper { return [lower, upper] }
        let paddedUpper = upper > 0 ? upper * 1.15 : 1
        return [lower, paddedUpper]
    }

    /// Room above the tallest bar so value labels are not clipped.
    static func barValueHeadroom(maxValue: Double) -> [Double] {
        guard maxValue.isFinite, maxValue > 0 else { return [0, 1] }
        return [0, maxValue * 1.28]
    }

    static func barValueLabelFont(barCount: Int) -> Font {
        let size: CGFloat
        switch barCount {
        case ...8: size = 9
        case ...14: size = 7.5
        default: size = 6.5
        }
        return .system(size: size, weight: .semibold, design: .rounded)
    }

    private static func stableHash(_ string: String) -> Int {
        var hash = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return abs(hash)
    }
}

extension View {
    func chartStatsYAxisStyle() -> some View {
        chartYAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel()
                    .font(.caption2)
            }
        }
    }

    /// Labels only, faint grid — Stats cards, not Vehicle Care mini charts.
    func chartStatsQuietYAxisStyle() -> some View {
        chartYAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.10))
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func chartBarValueHeadroom(maxValue: Double) -> some View {
        chartYScale(domain: StatsChartTheme.barValueHeadroom(maxValue: maxValue))
    }

    /// Dashed vertical grid + centered date labels (trip daily / cost timeline parity).
    func chartStatsDateXAxis(
        values: [Date],
        label: @escaping (Date) -> String
    ) -> some View {
        chartXAxis {
            AxisMarks(values: values) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                AxisTick()
                if let date = value.as(Date.self) {
                    AxisValueLabel(centered: true) {
                        Text(label(date))
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
        }
    }

    func chartStatsAxisStyle() -> some View {
        chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .chartStatsYAxisStyle()
    }

    func chartStatsAppearAnimation(reduceMotion: Bool) -> some View {
        modifier(StatsChartAppearModifier(reduceMotion: reduceMotion))
    }

    func statsChartCardLayout() -> some View {
        chartPlotStyle { plot in
            plot
                .padding(.horizontal, StatsChartTheme.plotHorizontalInset)
                .padding(.vertical, StatsChartTheme.plotVerticalInset)
        }
        .padding(.horizontal, StatsChartTheme.chartCardHorizontalPadding)
        .frame(maxWidth: .infinity)
    }
}

struct StatsBarValueLabel: View {
    let text: String
    var barCount: Int = 7

    var body: some View {
        Text(text)
            .font(StatsChartTheme.barValueLabelFont(barCount: barCount))
            .foregroundStyle(Color.primary.opacity(0.78))
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .monospacedDigit()
            .allowsTightening(true)
    }
}

private struct StatsChartAppearModifier: ViewModifier {
    let reduceMotion: Bool
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .onAppear {
                guard !appeared else { return }
                if reduceMotion {
                    appeared = true
                } else {
                    withAnimation(.easeOut(duration: 0.35)) {
                        appeared = true
                    }
                }
            }
    }
}
