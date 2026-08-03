import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    // Deliberately no `@Query` for trips: the stats tab only ever aggregates the selected period,
    // so it fetches that window instead of pulling the whole library into memory.
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Query private var vehicles: [VehicleProfile]
    @Environment(\.modelContext) private var modelContext
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedPeriod: StatsPeriod = .week
    @State private var selectedCategoryID: String?
    @State private var selectedVehicleID: UUID?
    @State private var selectedMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEnd = Date()
    @State private var animatedProgress: Double = 0
    @State private var snapshot: StatsDisplaySnapshot?
    @State private var snapshotRefreshTask: Task<Void, Never>?
    @State private var earliestTripStart: Date?
    /// Bumped whenever the store reports a save, standing in for the change tracking a `@Query`
    /// would have given us.
    @State private var storeVersion = 0
    @State private var snapshotLoader: StatsSnapshotLoader?
    @Namespace private var periodChipNamespace

    private var snap: StatsDisplaySnapshot {
        snapshot ?? .empty
    }

    private var snapshotInputs: StatsSnapshotInputs {
        StatsSnapshotInputs(
            storeVersion: storeVersion,
            categoryCount: categories.count,
            vehicleCount: vehicles.count,
            period: selectedPeriod,
            customStart: customStart,
            customEnd: customEnd,
            selectedMonth: selectedMonth,
            selectedCategoryID: selectedCategoryID,
            selectedVehicleID: selectedVehicleID
        )
    }

    private var goalMonth: Date {
        StatsViewModel.goalMonth(
            for: selectedPeriod,
            selectedMonth: selectedMonth,
            customStart: customStart,
            customEnd: customEnd
        )
    }

    private var goalTargetMeters: Double {
        settings.goalMeters(forMonthContaining: goalMonth)
    }

    private var isGoalEditable: Bool {
        settings.isGoalEditable(forMonthContaining: goalMonth)
    }

    private var goalProgress: Double {
        guard goalTargetMeters > 0 else { return 0 }
        return min(1, snap.goalDistanceMeters / goalTargetMeters)
    }

    private var goalPercentText: String {
        "\(Int(goalProgress * 100))%"
    }

    private var goalRangeLabel: String {
        DateFormatters.monthYear.string(from: goalMonth)
    }

    /// Date window the summary and charts aggregate over (not the goal month).
    private var statsPeriodScopeLabel: String {
        switch selectedPeriod {
        case .week:
            return selectedPeriod.title
        case .month:
            return DateFormatters.monthYear.string(from: selectedMonth)
        case .custom:
            let start = DateFormatters.chartDay.string(from: min(customStart, customEnd))
            let end = DateFormatters.chartDay.string(from: max(customStart, customEnd))
            return "\(start) – \(end)"
        }
    }

    /// Period plus any active category/vehicle filters — used where those filters apply (summary).
    private var statsSummaryScopeLabel: String {
        var parts = [statsPeriodScopeLabel]
        if selectedCategoryID != nil {
            parts.append(selectedCategoryName)
        }
        if selectedVehicleID != nil {
            parts.append(selectedVehicleName)
        }
        return parts.joined(separator: " · ")
    }

    private func titledWithScope(_ baseKey: StaticString, scope: String) -> String {
        String(format: L10n.string("stats.title.with_scope"), L10n.string(baseKey), scope)
    }

    var body: some View {
        let fuelCurrencyCode = settings.fuelCurrency.rawValue
        List {
            statsFilterCard
                .glassListRow()

            Section(L10n.string("stats.goal.section")) {
                HStack(spacing: 20) {
                    goalRing
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("stats.goal.monthly"))
                            .font(.subheadline.weight(.semibold))
                        Text(goalRangeLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(DateFormatters.formatDistance(snap.goalDistanceMeters)) / \(DateFormatters.formatDistance(goalTargetMeters))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isGoalEditable {
                            Stepper(
                                value: Binding(
                                    get: { Int(goalTargetMeters / 1000) },
                                    set: { newValue in
                                        settings.setMonthlyGoalMeters(Double(newValue) * 1000)
                                        TrailhoundHaptics.selection()
                                    }
                                ),
                                in: 50...2000,
                                step: 50
                            ) {
                                Text(L10n.string("stats.goal.target_km"))
                                    .font(.caption)
                            }
                        } else {
                            Text("\(L10n.string("stats.goal.target_km")): \(DateFormatters.formatDistance(goalTargetMeters))")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 4)
                .glassListRow()
            }

            Section(titledWithScope("stats.summary.section", scope: statsSummaryScopeLabel)) {
                trendRow(L10n.string("stats.trips"), value: "\(snap.stats.tripCount)", trend: snap.tripCountTrendText())
                    .glassRow(position: .first)
                trendRow(L10n.string("stats.total_distance"), value: snap.stats.totalDistanceText, trend: snap.distanceTrendText())
                    .glassRow(position: .middle)
                trendRow(L10n.string("stats.total_duration"), value: snap.stats.totalDurationText, trend: snap.durationTrendText())
                    .glassRow(position: .middle)
                statRow(L10n.string("stats.average_duration"), value: snap.stats.averageDurationText)
                    .glassRow(position: .middle)
                trendRow(L10n.string("stats.average_speed"), value: snap.stats.averageSpeedText, trend: snap.averageSpeedTrendText())
                    .glassRow(position: .middle)
                trendRow(L10n.string("stats.max_speed"), value: snap.stats.maxSpeedText, trend: snap.maxSpeedTrendText())
                    .glassRow(position: .middle)
                trendRow(
                    L10n.estimatedFuel,
                    value: FuelCostCalculator.formatCost(snap.stats.estimatedFuelCost, currencyCode: fuelCurrencyCode),
                    trend: snap.fuelCostTrendText()
                )
                    .glassRow(position: .middle)
                statRow(
                    L10n.string("stats.cost_per_km"),
                    value: snap.stats.costPerKm > 0
                        ? FuelCostCalculator.formatCost(snap.stats.costPerKm, currencyCode: fuelCurrencyCode)
                        : "—"
                )
                    .glassRow(position: .middle)
                statRow(
                    L10n.string("stats.average_cost_per_trip"),
                    value: snap.stats.averageCostPerTrip > 0
                        ? FuelCostCalculator.formatCost(snap.stats.averageCostPerTrip, currencyCode: fuelCurrencyCode)
                        : "—"
                )
                    .glassRow(position: .middle)
                statRow(L10n.string("stats.night_driving"), value: snap.stats.nightDrivingText)
                    .glassRow(position: .last)
            }
            .transition(TrailhoundMotion.fadeScaleTransition(reduceMotion: reduceMotion))
            .id(fuelCurrencyCode)

            if snap.hasAnyDailyChart {
                Section(titledWithScope("stats.chart.daily_section", scope: statsPeriodScopeLabel)) {
                    if !snap.dailyDistance.isEmpty {
                        StatsDeferredChart(
                            title: titledWithScope("stats.chart.weekly_distance", scope: statsPeriodScopeLabel),
                            chartHeight: 200,
                            reduceMotion: reduceMotion
                        ) {
                            dailyDistanceChartBody(snap.dailyDistance)
                        }
                        .frame(maxWidth: .infinity)
                        .statsPairedChartCard()
                        .statsPairedChartsListRow()
                    }
                    if !snap.dailyDuration.isEmpty {
                        StatsDeferredChart(
                            title: titledWithScope("stats.chart.weekly_duration", scope: statsPeriodScopeLabel),
                            chartHeight: 200,
                            reduceMotion: reduceMotion
                        ) {
                            dailyDurationChartBody(snap.dailyDuration)
                        }
                        .frame(maxWidth: .infinity)
                        .statsPairedChartCard()
                        .statsPairedChartsListRow()
                    }
                    if !snap.dailyAverageSpeed.isEmpty {
                        StatsDeferredChart(
                            title: titledWithScope("stats.chart.daily_average_speed", scope: statsPeriodScopeLabel),
                            chartHeight: 200,
                            reduceMotion: reduceMotion
                        ) {
                            dailyAverageSpeedChartBody(snap.dailyAverageSpeed)
                        }
                        .frame(maxWidth: .infinity)
                        .statsPairedChartCard()
                        .statsPairedChartsListRow()
                    }
                    if !snap.dailyMaxSpeed.isEmpty {
                        StatsDeferredChart(
                            title: titledWithScope("stats.chart.daily_max_speed", scope: statsPeriodScopeLabel),
                            chartHeight: 200,
                            reduceMotion: reduceMotion
                        ) {
                            dailyMaxSpeedChartBody(snap.dailyMaxSpeed)
                        }
                        .frame(maxWidth: .infinity)
                        .statsPairedChartCard()
                        .statsPairedChartsListRow()
                    }
                    if !snap.dailyFuelCost.isEmpty {
                        StatsDeferredChart(
                            title: titledWithScope("stats.chart.daily_fuel", scope: statsPeriodScopeLabel),
                            chartHeight: 200,
                            reduceMotion: reduceMotion
                        ) {
                            dailyFuelCostChartBody(snap.dailyFuelCost)
                        }
                        .frame(maxWidth: .infinity)
                        .statsPairedChartCard()
                        .statsPairedChartsListRow()
                    }
                }
                .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedPeriod)
            }

            if snap.showsVehicleBreakdownCharts {
                Section(titledWithScope("stats.chart.vehicles_section", scope: statsPeriodScopeLabel)) {
                    StatsDeferredContent(placeholderHeight: 220, reduceMotion: reduceMotion) {
                        vehicleDistanceDonut(data: snap.vehicleDistance)
                    }
                    .frame(maxWidth: .infinity)
                    .statsPairedChartCard()
                    .statsPairedChartsListRow()

                    if !snap.vehicleDuration.isEmpty {
                        StatsDeferredContent(placeholderHeight: 220, reduceMotion: reduceMotion) {
                            vehicleDurationDonut(data: snap.vehicleDuration)
                        }
                        .frame(maxWidth: .infinity)
                        .statsPairedChartCard()
                        .statsPairedChartsListRow()
                    }

                    if !snap.vehicleFuelCost.isEmpty {
                        StatsDeferredContent(placeholderHeight: 220, reduceMotion: reduceMotion) {
                            vehicleFuelDonut(data: snap.vehicleFuelCost)
                        }
                        .frame(maxWidth: .infinity)
                        .statsPairedChartCard()
                        .statsPairedChartsListRow()
                    }
                }
            }

            if snap.hasCategoryCharts {
                Section(titledWithScope("stats.chart.categories_section", scope: statsPeriodScopeLabel)) {
                    if !snap.categoryDistance.isEmpty {
                        StatsDeferredContent(placeholderHeight: 220, reduceMotion: reduceMotion) {
                            categoryDistanceDonut(data: snap.categoryDistance)
                        }
                        .frame(maxWidth: .infinity)
                        .statsPairedChartCard()
                        .statsPairedChartsListRow()
                    }
                    if !snap.categoryDuration.isEmpty {
                        StatsDeferredContent(placeholderHeight: 220, reduceMotion: reduceMotion) {
                            categoryDurationDonut(data: snap.categoryDuration)
                        }
                        .frame(maxWidth: .infinity)
                        .statsPairedChartCard()
                        .statsPairedChartsListRow()
                    }
                    if !snap.categoryFuelCost.isEmpty {
                        StatsDeferredContent(placeholderHeight: 220, reduceMotion: reduceMotion) {
                            categoryFuelDonut(data: snap.categoryFuelCost)
                        }
                        .frame(maxWidth: .infinity)
                        .statsPairedChartCard()
                        .statsPairedChartsListRow()
                    }
                }
                .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedCategoryID)
            }
        }
        .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedPeriod)
        .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedCategoryID)
        .glassListChrome()
        .navigationTitle(L10n.string("stats.title"))
        .onAppear {
            if snapshotLoader == nil {
                snapshotLoader = StatsSnapshotLoader(modelContainer: modelContext.container)
            }
            refreshEarliestTripStart()
            normalizeSelectedMonth()
            updateAnimatedProgress(animated: false)
            scheduleSnapshotRefresh()
        }
        .onStoreSave {
            refreshEarliestTripStart()
            storeVersion &+= 1
        }
        .onChange(of: snapshotInputs) { _, _ in
            scheduleSnapshotRefresh()
        }
        .onChange(of: selectedPeriod) { _, newPeriod in
            if newPeriod == .month {
                normalizeSelectedMonth()
            }
        }
        .onChange(of: goalProgress) { _, _ in
            updateAnimatedProgress(animated: true)
        }
        .onChange(of: snap.goalDistanceMeters) { _, _ in
            updateAnimatedProgress(animated: true)
        }
        .onChange(of: goalTargetMeters) { _, _ in
            updateAnimatedProgress(animated: true)
        }
        .onDisappear {
            snapshotRefreshTask?.cancel()
        }
    }

    private func scheduleSnapshotRefresh() {
        snapshotRefreshTask?.cancel()

        let isFirstLoad = snapshot == nil
        let loader = snapshotLoader ?? StatsSnapshotLoader(modelContainer: modelContext.container)
        if snapshotLoader == nil {
            snapshotLoader = loader
        }

        let request = StatsSnapshotRequest(
            storeVersion: storeVersion,
            selectedPeriod: selectedPeriod,
            customStart: customStart,
            customEnd: customEnd,
            selectedMonth: selectedMonth,
            goalMonth: goalMonth,
            selectedCategoryID: selectedCategoryID,
            selectedVehicleID: selectedVehicleID,
            categoryNames: StatsViewModel.categoryNameMap(for: categories),
            vehicleNames: StatsViewModel.vehicleNameMap(for: vehicles),
            vehicleCount: vehicles.count
        )

        snapshotRefreshTask = Task {
            if !isFirstLoad {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled else { return }
            let built = await loader.snapshot(for: request)
            guard !Task.isCancelled else { return }
            await MainActor.run { snapshot = built }
        }
    }

    private func refreshEarliestTripStart() {
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        earliestTripStart = (try? modelContext.fetch(descriptor))?.first?.startedAt
    }

    private func normalizeSelectedMonth() {
        selectedMonth = StatsViewModel.clampedMonth(
            selectedMonth,
            earliestTripStart: earliestTripStart
        )
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

            if selectedPeriod == .month {
                statsMonthPicker
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }

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

    private var selectableMonths: [Date] {
        StatsViewModel.selectableMonths(earliestTripStart: earliestTripStart)
    }

    private var selectedMonthTitle: String {
        DateFormatters.monthYear.string(from: selectedMonth)
    }

    private var canGoToPreviousMonth: Bool {
        guard let earliest = selectableMonths.last else { return false }
        let selectedStart = StatsViewModel.calendarMonthInterval(containing: selectedMonth).start
        return selectedStart > earliest
    }

    private var canGoToNextMonth: Bool {
        let selectedStart = StatsViewModel.calendarMonthInterval(containing: selectedMonth).start
        let currentStart = StatsViewModel.calendarMonthInterval(containing: Date()).start
        return selectedStart < currentStart
    }

    private var selectedMonthBinding: Binding<Date> {
        Binding(
            get: {
                StatsViewModel.clampedMonth(
                    selectedMonth,
                    earliestTripStart: earliestTripStart
                )
            },
            set: { newValue in
                selectedMonth = StatsViewModel.clampedMonth(
                    newValue,
                    earliestTripStart: earliestTripStart
                )
            }
        )
    }

    private var statsMonthPicker: some View {
        HStack(spacing: 10) {
            Button {
                selectedMonth = StatsViewModel.clampedMonth(
                    StatsViewModel.shiftMonth(selectedMonth, by: -1),
                    earliestTripStart: earliestTripStart
                )
                TrailhoundHaptics.selection()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!canGoToPreviousMonth)
            .accessibilityLabel(L10n.string("stats.period.previous_month"))

            Picker(L10n.string("stats.period.select_month"), selection: selectedMonthBinding) {
                ForEach(selectableMonths, id: \.self) { month in
                    Text(DateFormatters.monthYear.string(from: month))
                        .tag(month)
                }
            }
            .pickerStyle(.menu)
            .tint(TrailhoundBrandColors.brandBottom)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(L10n.string("stats.period.select_month"))
            .accessibilityValue(selectedMonthTitle)

            Button {
                selectedMonth = StatsViewModel.clampedMonth(
                    StatsViewModel.shiftMonth(selectedMonth, by: 1),
                    earliestTripStart: earliestTripStart
                )
                TrailhoundHaptics.selection()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(!canGoToNextMonth)
            .accessibilityLabel(L10n.string("stats.period.next_month"))
        }
        .onAppear {
            selectedMonth = StatsViewModel.clampedMonth(
                selectedMonth,
                earliestTripStart: earliestTripStart
            )
        }
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
        .accessibilityValue("\(goalPercentText), \(goalRangeLabel)")
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
            snap.dailyDistance.count,
            snap.dailyDuration.count,
            snap.dailyAverageSpeed.count,
            snap.dailyMaxSpeed.count,
            snap.dailyFuelCost.count,
            1
        )
    }

    /// Keep x-axis readable: daily for week, weekly ticks for month-sized ranges.
    private var dailyAxisLabelStride: Int {
        switch selectedPeriod {
        case .week:
            return 1
        case .month:
            return 5
        case .custom:
            switch dailyChartDayCount {
            case ...10: return 1
            case ...20: return 2
            default: return 5
            }
        }
    }

    private func dailyAxisDayLabel(_ date: Date) -> String {
        DateFormatters.chartDay.string(from: date)
    }

    private func dailyAxisLabelDates(from days: [Date]) -> [Date] {
        let stride = dailyAxisLabelStride
        return days.enumerated().compactMap { index, day in
            (index % stride == 0 || index == days.count - 1) ? day : nil
        }
    }

    @AxisContentBuilder
    private func dailyChartXAxis(days: [Date]) -> some AxisContent {
        AxisMarks(values: dailyAxisLabelDates(from: days)) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
            AxisTick()
            if let date = value.as(Date.self) {
                AxisValueLabel(centered: true) {
                    Text(dailyAxisDayLabel(date))
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }

    private func dailyDistanceChartBody(_ dailyChartData: [DailyDistance]) -> some View {
        let days = dailyChartData.map(\.day)
        return Chart(dailyChartData) { item in
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

    private func dailyDurationChartBody(_ dailyDurationChartData: [DailyDuration]) -> some View {
        let days = dailyDurationChartData.map(\.day)
        return Chart(dailyDurationChartData) { item in
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

    private func dailyAverageSpeedChartBody(_ dailyAverageSpeedChartData: [DailyAverageSpeed]) -> some View {
        let days = dailyAverageSpeedChartData.map(\.day)
        return Chart(dailyAverageSpeedChartData) { item in
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

    private func dailyMaxSpeedChartBody(_ dailyMaxSpeedChartData: [DailyMaxSpeed]) -> some View {
        let days = dailyMaxSpeedChartData.map(\.day)
        return Chart(dailyMaxSpeedChartData) { item in
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

    private func dailyFuelCostChartBody(_ dailyFuelCostChartData: [DailyFuelCost]) -> some View {
        let days = dailyFuelCostChartData.map(\.day)
        return Chart(dailyFuelCostChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.fuel_cost"), item.cost)
            )
            .foregroundStyle(statsFuelCostBarFill)
        }
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.fuel_cost"))
        .frame(height: 200)
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

    private var statsFuelCostBarFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.34, green: 0.82, blue: 0.58),
                Color(red: 0.28, green: 0.78, blue: 0.86)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func statsDonutLegendRow(
        name: String,
        durationStyle: Bool,
        domainNames: [String],
        @ViewBuilder value: () -> some View
    ) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(StatsChartSliceColors.color(for: name, durationStyle: durationStyle, domain: domainNames))
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

    private func vehicleDistanceDonut(data vehicleChartData: [VehicleDistance]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titledWithScope("stats.chart.vehicles", scope: statsPeriodScopeLabel))
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
                statsDonutLegendRow(
                    name: item.name,
                    durationStyle: false,
                    domainNames: vehicleChartData.map(\.name)
                ) {
                    Text(DateFormatters.formatDistance(item.distanceMeters))
                }
            }
        }
    }

    private func vehicleDurationDonut(data vehicleDurationChartData: [VehicleDuration]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titledWithScope("stats.chart.vehicles_duration", scope: statsPeriodScopeLabel))
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
                statsDonutLegendRow(
                    name: item.name,
                    durationStyle: true,
                    domainNames: vehicleDurationChartData.map(\.name)
                ) {
                    Text(DateFormatters.formatDuration(item.duration))
                }
            }
        }
    }

    private func categoryDistanceDonut(data categoryChartData: [CategoryDistance]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titledWithScope("stats.chart.categories", scope: statsPeriodScopeLabel))
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
                statsDonutLegendRow(
                    name: item.name,
                    durationStyle: false,
                    domainNames: categoryChartData.map(\.name)
                ) {
                    Text(DateFormatters.formatDistance(item.distanceMeters))
                }
            }
        }
    }

    private func categoryDurationDonut(data categoryDurationChartData: [CategoryDuration]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titledWithScope("stats.chart.categories_duration", scope: statsPeriodScopeLabel))
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
                statsDonutLegendRow(
                    name: item.name,
                    durationStyle: true,
                    domainNames: categoryDurationChartData.map(\.name)
                ) {
                    Text(DateFormatters.formatDuration(item.duration))
                }
            }
        }
    }

    private func vehicleFuelDonut(data vehicleFuelChartData: [VehicleFuelCost]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titledWithScope("stats.chart.vehicles_fuel", scope: statsPeriodScopeLabel))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Chart(vehicleFuelChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.fuel_cost"), item.cost),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value(L10n.string("filter.vehicle"), item.name))
            }
            .chartForegroundStyleScale(
                domain: chartSlicePalette(for: vehicleFuelChartData.map(\.name), durationStyle: false).0,
                range: chartSlicePalette(for: vehicleFuelChartData.map(\.name), durationStyle: false).1
            )
            .statsHiddenDonutLegend(height: 140)
            ForEach(vehicleFuelChartData) { item in
                statsDonutLegendRow(
                    name: item.name,
                    durationStyle: false,
                    domainNames: vehicleFuelChartData.map(\.name)
                ) {
                    Text(FuelCostCalculator.formatCost(item.cost, currencyCode: AppSettings.shared.fuelCurrency.rawValue))
                }
            }
        }
    }

    private func categoryFuelDonut(data categoryFuelChartData: [CategoryFuelCost]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titledWithScope("stats.chart.categories_fuel", scope: statsPeriodScopeLabel))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Chart(categoryFuelChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.fuel_cost"), item.cost),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value(L10n.string("filter.category"), item.name))
            }
            .chartForegroundStyleScale(
                domain: chartSlicePalette(for: categoryFuelChartData.map(\.name), durationStyle: false).0,
                range: chartSlicePalette(for: categoryFuelChartData.map(\.name), durationStyle: false).1
            )
            .statsHiddenDonutLegend(height: 140)
            ForEach(categoryFuelChartData) { item in
                statsDonutLegendRow(
                    name: item.name,
                    durationStyle: false,
                    domainNames: categoryFuelChartData.map(\.name)
                ) {
                    Text(FuelCostCalculator.formatCost(item.cost, currencyCode: AppSettings.shared.fuelCurrency.rawValue))
                }
            }
        }
    }
}

private struct StatsSnapshotInputs: Equatable {
    let storeVersion: Int
    let categoryCount: Int
    let vehicleCount: Int
    let period: StatsPeriod
    let customStart: Date
    let customEnd: Date
    let selectedMonth: Date
    let selectedCategoryID: String?
    let selectedVehicleID: UUID?
}

/// Distinct slice hues for donut charts; same label → same color when it appears in the same domain.
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

    private static func colorMap(for domain: [String], durationStyle: Bool) -> [String: Color] {
        let palette = durationStyle ? duration : distance
        let ordered = Array(Set(domain)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var map: [String: Color] = [:]
        for (index, name) in ordered.enumerated() {
            map[name] = palette[index % palette.count]
        }
        return map
    }

    static func color(for name: String, durationStyle: Bool, domain: [String]) -> Color {
        colorMap(for: domain, durationStyle: durationStyle)[name] ?? (durationStyle ? duration[0] : distance[0])
    }

    static func scale(for names: [String], durationStyle: Bool) -> ([String], [Color]) {
        let map = colorMap(for: names, durationStyle: durationStyle)
        return (names, names.map { map[$0]! })
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
