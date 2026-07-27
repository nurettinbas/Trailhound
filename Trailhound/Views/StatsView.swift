import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Query private var vehicles: [VehicleProfile]
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedPeriod: StatsPeriod = .week
    @State private var selectedCategoryID: String?
    @State private var selectedVehicleID: UUID?
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var animatedProgress: Double = 0
    @Namespace private var periodChipNamespace

    private var completedTrips: [Trip] {
        trips.filter { $0.endedAt != nil }
    }

    private var selectedInterval: DateInterval {
        StatsViewModel.interval(for: selectedPeriod, customStart: customStart, customEnd: customEnd)
    }

    private var previousInterval: DateInterval {
        StatsViewModel.previousInterval(for: selectedInterval)
    }

    private var periodTrips: [Trip] {
        StatsViewModel.trips(in: selectedInterval, from: completedTrips)
    }

    private var previousTrips: [Trip] {
        StatsViewModel.trips(in: previousInterval, from: completedTrips)
    }

    private var stats: TripStats {
        StatsViewModel.stats(for: periodTrips, categoryID: selectedCategoryID, vehicleID: selectedVehicleID)
    }

    private var previousStats: TripStats {
        StatsViewModel.stats(for: previousTrips, categoryID: selectedCategoryID, vehicleID: selectedVehicleID)
    }

    private var distanceTrendText: String? {
        StatsViewModel.trendText(
            current: stats.totalDistanceMeters,
            previous: previousStats.totalDistanceMeters
        )
    }

    private var tripCountTrendText: String? {
        StatsViewModel.trendText(
            current: Double(stats.tripCount),
            previous: Double(previousStats.tripCount)
        )
    }

    private var durationTrendText: String? {
        StatsViewModel.trendText(
            current: stats.totalDuration,
            previous: previousStats.totalDuration
        )
    }

    private var averageSpeedTrendText: String? {
        StatsViewModel.trendText(
            current: stats.averageSpeedKmh,
            previous: previousStats.averageSpeedKmh
        )
    }

    private var maxSpeedTrendText: String? {
        StatsViewModel.trendText(
            current: stats.maxSpeedKmh,
            previous: previousStats.maxSpeedKmh
        )
    }

    private var dailyChartData: [DailyDistance] {
        StatsViewModel.dailyDistances(in: selectedInterval, from: completedTrips)
    }

    private var dailyDurationChartData: [DailyDuration] {
        StatsViewModel.dailyDurations(in: selectedInterval, from: completedTrips)
    }

    private var dailyAverageSpeedChartData: [DailyAverageSpeed] {
        StatsViewModel.dailyAverageSpeeds(in: selectedInterval, from: completedTrips)
    }

    private var dailyMaxSpeedChartData: [DailyMaxSpeed] {
        StatsViewModel.dailyMaxSpeeds(in: selectedInterval, from: completedTrips)
    }

    private var categoryChartData: [CategoryDistance] {
        StatsViewModel.categoryBreakdown(for: periodTrips, categories: categories)
    }

    private var categoryDurationChartData: [CategoryDuration] {
        StatsViewModel.categoryDurationBreakdown(for: periodTrips, categories: categories)
    }

    private var vehicleChartData: [VehicleDistance] {
        StatsViewModel.vehicleBreakdown(for: periodTrips, vehicles: vehicles)
    }

    private var vehicleDurationChartData: [VehicleDuration] {
        StatsViewModel.vehicleDurationBreakdown(for: periodTrips, vehicles: vehicles)
    }

    private var showsVehicleBreakdownCharts: Bool {
        !vehicleChartData.isEmpty && (vehicles.count > 1 || vehicleChartData.count > 1)
    }

    private var monthInterval: DateInterval {
        let end = Date()
        let start = Calendar.current.date(byAdding: .month, value: -1, to: end) ?? end
        return DateInterval(start: start, end: end)
    }

    private var monthDistanceMeters: Double {
        StatsViewModel.stats(
            for: StatsViewModel.trips(in: monthInterval, from: completedTrips)
        ).totalDistanceMeters
    }

    private var goalProgress: Double {
        guard settings.monthlyDistanceGoalMeters > 0 else { return 0 }
        return min(1, monthDistanceMeters / settings.monthlyDistanceGoalMeters)
    }

    private var goalPercentText: String {
        "\(Int(goalProgress * 100))%"
    }

    var body: some View {
        List {
            statsFilterCard
                .glassListRow()

            Section(L10n.string("stats.goal.section")) {
                HStack(spacing: 20) {
                    goalRing
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("stats.goal.monthly"))
                            .font(.subheadline.weight(.semibold))
                        Text("\(DateFormatters.formatDistance(monthDistanceMeters)) / \(DateFormatters.formatDistance(settings.monthlyDistanceGoalMeters))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Stepper(
                            value: Binding(
                                get: { Int(settings.monthlyDistanceGoalMeters / 1000) },
                                set: { newValue in
                                    settings.monthlyDistanceGoalMeters = Double(newValue) * 1000
                                    TrailhoundHaptics.selection()
                                }
                            ),
                            in: 50...2000,
                            step: 50
                        ) {
                            Text(L10n.string("stats.goal.target_km"))
                                .font(.caption)
                        }
                    }
                }
                .padding(.vertical, 4)
                .glassListRow()
            }

            Section(L10n.string("stats.summary.section")) {
                trendRow(L10n.string("stats.trips"), value: "\(stats.tripCount)", trend: tripCountTrendText)
                    .glassRow(position: .first)
                trendRow(L10n.string("stats.total_distance"), value: stats.totalDistanceText, trend: distanceTrendText)
                    .glassRow(position: .middle)
                trendRow(L10n.string("stats.total_duration"), value: stats.totalDurationText, trend: durationTrendText)
                    .glassRow(position: .middle)
                statRow(L10n.string("stats.average_duration"), value: stats.averageDurationText)
                    .glassRow(position: .middle)
                trendRow(L10n.string("stats.average_speed"), value: stats.averageSpeedText, trend: averageSpeedTrendText)
                    .glassRow(position: .middle)
                trendRow(L10n.string("stats.max_speed"), value: stats.maxSpeedText, trend: maxSpeedTrendText)
                    .glassRow(position: .middle)
                statRow(L10n.estimatedFuel, value: stats.fuelCostText)
                    .glassRow(position: .middle)
                statRow(L10n.string("stats.night_driving"), value: stats.nightDrivingText)
                    .glassRow(position: .last)
            }
            .transition(TrailhoundMotion.fadeScaleTransition(reduceMotion: reduceMotion))

            if !dailyChartData.isEmpty || !dailyDurationChartData.isEmpty
                || !dailyAverageSpeedChartData.isEmpty || !dailyMaxSpeedChartData.isEmpty {
                Section(L10n.string("stats.chart.daily_section")) {
                    VStack(spacing: StatsChartPairTokens.cardSpacing) {
                        if !dailyChartData.isEmpty {
                            dailyDistanceChart
                                .frame(maxWidth: .infinity)
                                .statsPairedChartCard()
                        }
                        if !dailyDurationChartData.isEmpty {
                            dailyDurationChart
                                .frame(maxWidth: .infinity)
                                .statsPairedChartCard()
                        }
                        if !dailyAverageSpeedChartData.isEmpty {
                            dailyAverageSpeedChart
                                .frame(maxWidth: .infinity)
                                .statsPairedChartCard()
                        }
                        if !dailyMaxSpeedChartData.isEmpty {
                            dailyMaxSpeedChart
                                .frame(maxWidth: .infinity)
                                .statsPairedChartCard()
                        }
                    }
                    .statsPairedChartsListRow()
                }
                .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedPeriod)
            }

            if showsVehicleBreakdownCharts {
                Section(L10n.string("stats.chart.vehicles_section")) {
                    HStack(alignment: .top, spacing: StatsChartPairTokens.cardSpacing) {
                        vehicleDistanceDonut
                            .frame(maxWidth: .infinity)
                            .statsPairedChartCard()
                        if !vehicleDurationChartData.isEmpty {
                            vehicleDurationDonut
                                .frame(maxWidth: .infinity)
                                .statsPairedChartCard()
                        }
                    }
                    .statsPairedChartsListRow()
                }
            }

            if !categoryChartData.isEmpty || !categoryDurationChartData.isEmpty {
                Section(L10n.string("stats.chart.categories_section")) {
                    HStack(alignment: .top, spacing: StatsChartPairTokens.cardSpacing) {
                        if !categoryChartData.isEmpty {
                            categoryDistanceDonut
                                .frame(maxWidth: .infinity)
                                .statsPairedChartCard()
                        }
                        if !categoryDurationChartData.isEmpty {
                            categoryDurationDonut
                                .frame(maxWidth: .infinity)
                                .statsPairedChartCard()
                        }
                    }
                    .statsPairedChartsListRow()
                }
                .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedCategoryID)
            }
        }
        .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedPeriod)
        .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedCategoryID)
        .glassListChrome()
        .navigationTitle(L10n.string("stats.title"))
        .onAppear {
            updateAnimatedProgress(animated: false)
        }
        .onChange(of: goalProgress) { _, _ in
            updateAnimatedProgress(animated: true)
        }
        .onChange(of: monthDistanceMeters) { _, _ in
            updateAnimatedProgress(animated: true)
        }
    }

    private var selectedVehicleName: String {
        guard let selectedVehicleID,
              let vehicle = vehicles.first(where: { $0.id == selectedVehicleID }) else {
            return L10n.all
        }
        return vehicle.name
    }

    private var selectedCategoryName: String {
        guard let selectedCategoryID,
              let category = categories.first(where: { $0.storageKey == selectedCategoryID }) else {
            return L10n.all
        }
        return category.name
    }

    private var statsFilterCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(StatsPeriod.allCases) { period in
                    GlassFilterChip(
                        title: period.title,
                        isSelected: selectedPeriod == period,
                        namespace: periodChipNamespace,
                        highlightID: "statsPeriodHighlight",
                        expands: true
                    ) {
                        if reduceMotion {
                            selectedPeriod = period
                        } else {
                            withAnimation(TrailhoundMotion.gentle) {
                                selectedPeriod = period
                            }
                        }
                        TrailhoundHaptics.selection()
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.string("stats.period.title"))

            if selectedPeriod == .custom {
                HStack(alignment: .top, spacing: 10) {
                    statsCustomDateField(
                        title: L10n.string("stats.period.start"),
                        date: $customStart
                    )
                    statsCustomDateField(
                        title: L10n.string("stats.period.end"),
                        date: $customEnd
                    )
                }
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 12) {
                Text(L10n.string("filter.category"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Picker(L10n.string("filter.category"), selection: $selectedCategoryID) {
                    Text(L10n.all).tag(String?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(Optional(category.storageKey))
                    }
                }
                .pickerStyle(.menu)
                .tint(TrailhoundBrandColors.brandBottom)
                .labelsHidden()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.string("filter.category"))
            .accessibilityValue(selectedCategoryName)

            if !vehicles.isEmpty {
                HStack(spacing: 12) {
                    Text(L10n.string("filter.vehicle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Picker(L10n.string("filter.vehicle"), selection: $selectedVehicleID) {
                        Text(L10n.all).tag(UUID?.none)
                        ForEach(vehicles) { vehicle in
                            Text(vehicle.name).tag(Optional(vehicle.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(TrailhoundBrandColors.brandBottom)
                    .labelsHidden()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L10n.string("filter.vehicle"))
                .accessibilityValue(selectedVehicleName)
            }
        }
        .padding(.vertical, 6)
        .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedPeriod)
    }

    private func statsCustomDateField(title: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            DatePicker(title, selection: date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var goalRing: some View {
        ZStack {
            Circle()
                .stroke(Color.blue.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(goalPercentText)
                .font(.caption.bold())
                .numericTextAnimation(value: goalPercentText)
        }
        .frame(width: 72, height: 72)
        .accessibilityLabel(L10n.string("stats.goal.progress_accessibility"))
        .accessibilityValue(goalPercentText)
    }

    private func updateAnimatedProgress(animated: Bool) {
        if animated && !reduceMotion {
            withAnimation(TrailhoundMotion.cardSpring) {
                animatedProgress = goalProgress
            }
        } else {
            animatedProgress = goalProgress
        }
    }

    private func statRow(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func trendRow(_ title: String, value: String, trend: String?) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(value)
                    .foregroundStyle(.secondary)
                if let trend {
                    Text(trend)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trendColor(for: trend))
                        .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: trend)
                        .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
                }
            }
        }
    }

    private func trendColor(for trend: String) -> Color {
        if trend.hasPrefix("+") { return .green }
        if trend.hasPrefix("-") { return .red }
        return .secondary
    }

    private var dailyChartDayCount: Int {
        max(
            dailyChartData.count,
            dailyDurationChartData.count,
            dailyAverageSpeedChartData.count,
            dailyMaxSpeedChartData.count,
            1
        )
    }

    /// Keep x-axis readable: every day for short ranges, then every 2nd/3rd day.
    private var dailyAxisLabelStride: Int {
        switch dailyChartDayCount {
        case ...10: 1
        case ...20: 2
        default: 3
        }
    }

    private func dailyAxisDayLabel(_ date: Date) -> String {
        String(format: "%02d", Calendar.current.component(.day, from: date))
    }

    private func shouldShowDailyAxisLabel(for date: Date, in days: [Date]) -> Bool {
        guard let index = days.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: date) }) else {
            return false
        }
        let stride = dailyAxisLabelStride
        return index % stride == 0 || index == days.count - 1
    }

    @AxisContentBuilder
    private func dailyChartXAxis(days: [Date]) -> some AxisContent {
        AxisMarks(values: days) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
            AxisTick()
            if let date = value.as(Date.self), shouldShowDailyAxisLabel(for: date, in: days) {
                AxisValueLabel {
                    Text(dailyAxisDayLabel(date))
                        .font(.caption2.monospacedDigit())
                }
            }
        }
    }

    private var dailyDistanceChart: some View {
        let days = dailyChartData.map(\.day)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("stats.chart.weekly_distance"))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Chart(dailyChartData) { item in
                BarMark(
                    x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                    y: .value(L10n.string("stats.chart.distance_km"), item.distanceKilometers)
                )
                .foregroundStyle(TrailhoundBrandColors.brandBottom.gradient)
            }
            .chartXAxis { dailyChartXAxis(days: days) }
            .chartYAxisLabel(L10n.string("stats.chart.distance_km"))
            .frame(height: 200)
        }
    }

    private var dailyDurationChart: some View {
        let days = dailyDurationChartData.map(\.day)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("stats.chart.weekly_duration"))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Chart(dailyDurationChartData) { item in
                BarMark(
                    x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                    y: .value(L10n.string("stats.chart.duration_hours"), item.durationHours)
                )
                .foregroundStyle(statsDurationBarFill)
            }
            .chartXAxis { dailyChartXAxis(days: days) }
            .chartYAxisLabel(L10n.string("stats.chart.duration_hours"))
            .frame(height: 200)
        }
    }

    private var dailyAverageSpeedChart: some View {
        let days = dailyAverageSpeedChartData.map(\.day)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("stats.chart.daily_average_speed"))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Chart(dailyAverageSpeedChartData) { item in
                BarMark(
                    x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                    y: .value(L10n.string("stats.chart.speed_kmh"), item.speedKmh)
                )
                .foregroundStyle(statsAverageSpeedBarFill)
            }
            .chartXAxis { dailyChartXAxis(days: days) }
            .chartYAxisLabel(L10n.string("stats.chart.speed_kmh"))
            .frame(height: 200)
        }
    }

    private var dailyMaxSpeedChart: some View {
        let days = dailyMaxSpeedChartData.map(\.day)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("stats.chart.daily_max_speed"))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Chart(dailyMaxSpeedChartData) { item in
                BarMark(
                    x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                    y: .value(L10n.string("stats.chart.speed_kmh"), item.speedKmh)
                )
                .foregroundStyle(statsMaxSpeedBarFill)
            }
            .chartXAxis { dailyChartXAxis(days: days) }
            .chartYAxisLabel(L10n.string("stats.chart.speed_kmh"))
            .frame(height: 200)
        }
    }

    private var statsDurationBarFill: LinearGradient {
        LinearGradient(
            colors: [TrailhoundBrandColors.brandTop, TrailhoundBrandColors.atmosphereMid],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var statsAverageSpeedBarFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.58, blue: 0.24),
                Color(red: 0.92, green: 0.76, blue: 0.28)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var statsMaxSpeedBarFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.40, blue: 0.52),
                Color(red: 0.98, green: 0.58, blue: 0.24)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func statsDonutLegendRow(
        name: String,
        durationStyle: Bool,
        @ViewBuilder value: () -> some View
    ) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(StatsChartSliceColors.color(for: name, durationStyle: durationStyle))
                .frame(width: 8, height: 8)
            Text(name)
                .font(.caption2)
                .lineLimit(1)
            Spacer(minLength: 4)
            value()
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func chartSlicePalette(for names: [String], durationStyle: Bool) -> ([String], [Color]) {
        StatsChartSliceColors.scale(for: names, durationStyle: durationStyle)
    }

    private var vehicleDistanceDonut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("stats.chart.vehicles"))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Chart(vehicleChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.distance_km"), item.distanceKilometers),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value(L10n.string("filter.vehicle"), item.name))
            }
            .chartForegroundStyleScale(
                domain: chartSlicePalette(for: vehicleChartData.map(\.name), durationStyle: false).0,
                range: chartSlicePalette(for: vehicleChartData.map(\.name), durationStyle: false).1
            )
            .statsHiddenDonutLegend(height: 140)
            ForEach(vehicleChartData) { item in
                statsDonutLegendRow(name: item.name, durationStyle: false) {
                    Text(DateFormatters.formatDistance(item.distanceMeters))
                }
            }
        }
    }

    private var vehicleDurationDonut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("stats.chart.vehicles_duration"))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Chart(vehicleDurationChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.duration_hours"), item.durationHours),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value(L10n.string("filter.vehicle"), item.name))
            }
            .chartForegroundStyleScale(
                domain: chartSlicePalette(for: vehicleDurationChartData.map(\.name), durationStyle: true).0,
                range: chartSlicePalette(for: vehicleDurationChartData.map(\.name), durationStyle: true).1
            )
            .statsHiddenDonutLegend(height: 140)
            ForEach(vehicleDurationChartData) { item in
                statsDonutLegendRow(name: item.name, durationStyle: true) {
                    Text(DateFormatters.formatDuration(item.duration))
                }
            }
        }
    }

    private var categoryDistanceDonut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("stats.chart.categories"))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Chart(categoryChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.distance_km"), item.distanceKilometers),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value(L10n.string("filter.category"), item.name))
            }
            .chartForegroundStyleScale(
                domain: chartSlicePalette(for: categoryChartData.map(\.name), durationStyle: false).0,
                range: chartSlicePalette(for: categoryChartData.map(\.name), durationStyle: false).1
            )
            .statsHiddenDonutLegend(height: 140)
            ForEach(categoryChartData) { item in
                statsDonutLegendRow(name: item.name, durationStyle: false) {
                    Text(DateFormatters.formatDistance(item.distanceMeters))
                }
            }
        }
    }

    private var categoryDurationDonut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("stats.chart.categories_duration"))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Chart(categoryDurationChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.duration_hours"), item.durationHours),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value(L10n.string("filter.category"), item.name))
            }
            .chartForegroundStyleScale(
                domain: chartSlicePalette(for: categoryDurationChartData.map(\.name), durationStyle: true).0,
                range: chartSlicePalette(for: categoryDurationChartData.map(\.name), durationStyle: true).1
            )
            .statsHiddenDonutLegend(height: 140)
            ForEach(categoryDurationChartData) { item in
                statsDonutLegendRow(name: item.name, durationStyle: true) {
                    Text(DateFormatters.formatDuration(item.duration))
                }
            }
        }
    }
}

/// Distinct slice hues for donut charts; same label → same color index in distance & duration pairs.
private enum StatsChartSliceColors {
    static let distance: [Color] = [
        TrailhoundBrandColors.brandBottom,
        Color(red: 0.34, green: 0.82, blue: 0.58),
        Color(red: 0.98, green: 0.58, blue: 0.24),
        Color(red: 0.72, green: 0.48, blue: 0.95),
        Color(red: 0.95, green: 0.40, blue: 0.52),
        Color(red: 0.28, green: 0.78, blue: 0.86),
        Color(red: 0.92, green: 0.76, blue: 0.28),
        Color(red: 0.58, green: 0.64, blue: 0.92)
    ]

    static let duration: [Color] = [
        TrailhoundBrandColors.brandTop,
        Color(red: 0.48, green: 0.90, blue: 0.72),
        Color(red: 1.0, green: 0.72, blue: 0.42),
        Color(red: 0.82, green: 0.62, blue: 1.0),
        Color(red: 1.0, green: 0.55, blue: 0.68),
        Color(red: 0.45, green: 0.88, blue: 0.94),
        Color(red: 1.0, green: 0.88, blue: 0.45),
        Color(red: 0.70, green: 0.76, blue: 1.0)
    ]

    static func stableIndex(for name: String) -> Int {
        let hash = name.utf8.reduce(UInt64(5381)) { partial, byte in
            partial &* 33 &+ UInt64(byte)
        }
        let count = UInt64(distance.count)
        return Int(hash % count)
    }

    static func color(for name: String, durationStyle: Bool) -> Color {
        let palette = durationStyle ? duration : distance
        return palette[stableIndex(for: name)]
    }

    static func scale(for names: [String], durationStyle: Bool) -> ([String], [Color]) {
        (names, names.map { color(for: $0, durationStyle: durationStyle) })
    }
}

private enum StatsChartPairTokens {
    static let cardSpacing: CGFloat = 12
    static let cardContentInset: CGFloat = 10
}

private extension View {
    func statsHiddenDonutLegend(height: CGFloat) -> some View {
        chartLegend(.hidden)
            .frame(height: height)
    }

    func statsPairedChartCard() -> some View {
        glassCard(cornerRadius: GlassTokens.cardRadius, contentInset: StatsChartPairTokens.cardContentInset)
    }

    func statsPairedChartsListRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(
                    top: 6,
                    leading: GlassTokens.panelHorizontalInset,
                    bottom: 6,
                    trailing: GlassTokens.panelHorizontalInset
                )
            )
    }
}

#Preview {
    NavigationStack { StatsView() }
        .modelContainer(PreviewData.shared.container)
}
