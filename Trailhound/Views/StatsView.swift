import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    // Deliberately no `@Query` for trips: the stats tab only ever aggregates the selected period,
    // so it fetches that window instead of pulling the whole library into memory.
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Query private var vehicles: [VehicleProfile]
    @Query private var places: [SavedPlace]
    @Environment(\.modelContext) private var modelContext
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedPeriod: StatsPeriod = .week
    @State private var selectedCategoryID: String?
    @State private var selectedVehicleID: UUID?
    @State private var selectedPlaceID: UUID?
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
    @State private var costSnapshotLoader: VehicleCostSnapshotLoader?
    @State private var costSnapshot: VehicleCostSnapshot = .empty
    @State private var costRefreshTask: Task<Void, Never>?
    @State private var forecastLoader: MonthCostForecastLoader?
    @State private var forecast: MonthCostForecast = .empty
    @State private var recapLoader: YearRecapSnapshotLoader?
    @State private var recapSnapshot: YearRecapSnapshot?
    @State private var achievements: [AchievementDisplay] = []
    @State private var routeAggregates: [FrequentRouteAggregate] = []
    @State private var showForecastDetail = false
    @State private var showAchievements = false
    @State private var showRoutesMap = false
    @State private var showRecapStory = false
    @State private var unlockQueue: [AchievementDisplay] = []
    @Bindable private var tabSelection = TabSelection.shared
    @State private var dailyChartPage = 0
    @State private var vehicleChartPage = 0
    @State private var categoryChartPage = 0
    @Namespace private var periodChipNamespace

    private var snap: StatsDisplaySnapshot {
        snapshot ?? .empty
    }

    private var selectedPlaceName: String? {
        guard let selectedPlaceID else { return nil }
        return places.first(where: { $0.id == selectedPlaceID })?.name
    }

    private var sortedPlaces: [SavedPlace] {
        places.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var snapshotInputs: StatsSnapshotInputs {
        StatsSnapshotInputs(
            storeVersion: storeVersion,
            categoryCount: categories.count,
            vehicleCount: vehicles.count,
            placeCount: places.count,
            period: selectedPeriod,
            customStart: customStart,
            customEnd: customEnd,
            selectedMonth: selectedMonth,
            selectedCategoryID: selectedCategoryID,
            selectedVehicleID: selectedVehicleID,
            selectedPlaceID: selectedPlaceID,
            selectedPlaceName: selectedPlaceName
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

    /// Period plus any active category/vehicle/place filters — trip-based charts and summary.
    private var statsTripChartScopeLabel: String {
        var parts = [statsPeriodScopeLabel]
        if selectedCategoryID != nil {
            parts.append(selectedCategoryName)
        }
        if selectedVehicleID != nil {
            parts.append(selectedVehicleName)
        }
        if selectedPlaceID != nil {
            parts.append(selectedPlaceDisplayName)
        }
        return parts.joined(separator: " · ")
    }

    private var statsSummaryScopeLabel: String {
        statsTripChartScopeLabel
    }

    private var statsFilterFingerprint: String {
        [
            selectedPeriod.rawValue,
            String(selectedMonth.timeIntervalSince1970),
            String(customStart.timeIntervalSince1970),
            String(customEnd.timeIntervalSince1970),
            selectedCategoryID ?? "",
            selectedVehicleID?.uuidString ?? "",
            selectedPlaceID?.uuidString ?? "",
            selectedPlaceName ?? ""
        ].joined(separator: "|")
    }

    private func titledWithScope(_ baseKey: StaticString, scope: String) -> String {
        String(format: L10n.string("stats.title.with_scope"), L10n.string(baseKey), scope)
    }

    var body: some View {
        let fuelCurrencyCode = settings.fuelCurrency.rawValue
        List {
            Section(L10n.string("filter.title")) {
                statsFilterCard
                    .glassListRow()
            }

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
                .id("stats.goal")
            }

            Section(L10n.string("premium.section.title")) {
                YearRecapHubCard(
                    snapshot: recapSnapshot ?? .empty(year: Calendar.current.component(.year, from: Date())),
                    onPlay: { showRecapStory = true }
                )
                .glassListRow()

                StatsAchievementsStrip(achievements: achievements, onOpen: { showAchievements = true })
                    .glassListRow()

                FrequentRoutesPreviewCard(aggregates: routeAggregates, onOpen: { showRoutesMap = true })
                    .glassListRow()

                StatsForecastCard(
                    forecast: forecast,
                    currencyCode: fuelCurrencyCode,
                    onOpen: { showForecastDetail = true }
                )
                .glassListRow()
            }

            Section(titledWithScope("stats.summary.section", scope: statsSummaryScopeLabel)) {
                summaryMetricsGrid(currencyCode: fuelCurrencyCode)
                    .statsSummaryGlassRow(.only)
            }
            .transition(TrailhoundMotion.fadeScaleTransition(reduceMotion: reduceMotion))
            .id(fuelCurrencyCode)

            if snap.hasAnyDailyChart || costSnapshot.hasTimelineChart {
                Section(titledWithScope("stats.chart.daily_section", scope: statsTripChartScopeLabel)) {
                    StatsChartPager(
                        pageCount: dailyChartKinds.count,
                        contentHeight: dailyChartKinds.contains(.expenses)
                            ? StatsChartPagerMetrics.costContentHeight
                            : StatsChartPagerMetrics.dailyContentHeight,
                        selection: $dailyChartPage,
                        reduceMotion: reduceMotion
                    ) { index in
                        dailyChartPageContent(kind: dailyChartKinds[index], pageIndex: index)
                    }
                    .frame(maxWidth: .infinity)
                    .statsPairedChartCard()
                    .statsPairedChartsListRow()
                }
                .id("daily-\(statsFilterFingerprint)")
                .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedPeriod)
            }

            if snap.showsVehicleBreakdownCharts || costSnapshot.hasVehicleBreakdown {
                Section(titledWithScope("stats.chart.vehicles_section", scope: statsTripChartScopeLabel)) {
                    StatsChartPager(
                        pageCount: vehicleChartKinds.count,
                        contentHeight: StatsChartPagerMetrics.donutContentHeight,
                        selection: $vehicleChartPage,
                        reduceMotion: reduceMotion
                    ) { index in
                        vehicleChartPageContent(kind: vehicleChartKinds[index], pageIndex: index)
                    }
                    .frame(maxWidth: .infinity)
                    .statsPairedChartCard()
                    .statsPairedChartsListRow()
                }
                .id("vehicles-\(statsFilterFingerprint)")
            }

            if snap.hasCategoryCharts || costSnapshot.hasCategoryBreakdown {
                Section(titledWithScope("stats.chart.categories_section", scope: statsTripChartScopeLabel)) {
                    StatsChartPager(
                        pageCount: categoryChartKinds.count,
                        contentHeight: StatsChartPagerMetrics.donutContentHeight,
                        selection: $categoryChartPage,
                        reduceMotion: reduceMotion
                    ) { index in
                        categoryChartPageContent(kind: categoryChartKinds[index], pageIndex: index)
                    }
                    .frame(maxWidth: .infinity)
                    .statsPairedChartCard()
                    .statsPairedChartsListRow()
                }
                .id("categories-\(statsFilterFingerprint)")
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
            if costSnapshotLoader == nil {
                costSnapshotLoader = VehicleCostSnapshotLoader(modelContainer: modelContext.container)
            }
            if forecastLoader == nil {
                forecastLoader = MonthCostForecastLoader(modelContainer: modelContext.container)
            }
            if recapLoader == nil {
                recapLoader = YearRecapSnapshotLoader(modelContainer: modelContext.container)
            }
            refreshEarliestTripStart()
            normalizeSelectedMonth()
            updateAnimatedProgress(animated: false)
            scheduleSnapshotRefresh()
            scheduleCostSnapshotRefresh()
            schedulePremiumRefresh()
            consumeStatsDeepLink()
            maybeAutoplayRecap()
        }
        .onStoreSave {
            refreshEarliestTripStart()
            storeVersion &+= 1
        }
        .onChange(of: snapshotInputs) { _, _ in
            scheduleSnapshotRefresh()
            scheduleCostSnapshotRefresh()
            schedulePremiumRefresh()
        }
        .onChange(of: selectedPeriod) { _, newPeriod in
            if newPeriod == .month {
                normalizeSelectedMonth()
            }
            dailyChartPage = 0
            vehicleChartPage = 0
            categoryChartPage = 0
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
        .onChange(of: selectedCategoryID) { _, _ in
            dailyChartPage = 0
            categoryChartPage = 0
        }
        .onChange(of: selectedVehicleID) { _, _ in
            dailyChartPage = 0
            vehicleChartPage = 0
        }
        .onChange(of: selectedPlaceID) { _, _ in
            dailyChartPage = 0
            vehicleChartPage = 0
            categoryChartPage = 0
        }
        .onChange(of: selectedMonth) { _, _ in
            dailyChartPage = 0
            vehicleChartPage = 0
            categoryChartPage = 0
        }
        .onChange(of: customStart) { _, _ in
            dailyChartPage = 0
            vehicleChartPage = 0
            categoryChartPage = 0
        }
        .onChange(of: customEnd) { _, _ in
            dailyChartPage = 0
            vehicleChartPage = 0
            categoryChartPage = 0
        }
        .onDisappear {
            snapshotRefreshTask?.cancel()
        }
        .sheet(isPresented: $showForecastDetail) {
            StatsForecastDetailSheet(forecast: forecast, currencyCode: fuelCurrencyCode)
        }
        .sheet(isPresented: $showAchievements) {
            AchievementGalleryView(achievements: achievements)
        }
        .fullScreenCover(isPresented: $showRoutesMap) {
            FrequentRoutesMapView(aggregates: routeAggregates)
        }
        .fullScreenCover(isPresented: $showRecapStory) {
            YearRecapStoryView(snapshot: recapSnapshot ?? .empty(year: Calendar.current.component(.year, from: Date()))) {
                showRecapStory = false
                markRecapSeen()
            }
        }
        .overlay {
            if let item = unlockQueue.first {
                Color.black.opacity(0.28).ignoresSafeArea()
                AchievementUnlockOverlay(item: item) {
                    AchievementEvaluator.markSeen([item.id], in: modelContext)
                    if !unlockQueue.isEmpty {
                        unlockQueue.removeFirst()
                    }
                    try? modelContext.save()
                    achievements = AchievementEvaluator.displays(in: modelContext)
                }
            }
        }
    }

    private func scheduleCostSnapshotRefresh() {
        costRefreshTask?.cancel()
        let loader = costSnapshotLoader ?? VehicleCostSnapshotLoader(modelContainer: modelContext.container)
        if costSnapshotLoader == nil {
            costSnapshotLoader = loader
        }
        let interval = StatsViewModel.interval(
            for: selectedPeriod,
            customStart: customStart,
            customEnd: customEnd,
            selectedMonth: selectedMonth
        )
        let request = VehicleCostSnapshotRequest(
            storeVersion: storeVersion,
            periodStart: interval.start,
            periodEnd: interval.end,
            selectedVehicleID: selectedVehicleID
        )
        costRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let built = await loader.snapshot(for: request)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                costSnapshot = built
            }
        }
    }

    private func schedulePremiumRefresh() {
        let forecastActor = forecastLoader ?? MonthCostForecastLoader(modelContainer: modelContext.container)
        if forecastLoader == nil { forecastLoader = forecastActor }
        let recapActor = recapLoader ?? YearRecapSnapshotLoader(modelContainer: modelContext.container)
        if recapLoader == nil { recapLoader = recapActor }
        let year = Calendar.current.component(.year, from: Date())
        let request = MonthCostForecastRequest(
            storeVersion: storeVersion,
            selectedVehicleID: selectedVehicleID,
            now: Date()
        )
        Task {
            let builtForecast = await forecastActor.forecast(for: request)
            let builtRecap = await recapActor.snapshot(year: year, storeVersion: storeVersion)
            await MainActor.run {
                forecast = builtForecast
                recapSnapshot = builtRecap
                achievements = AchievementEvaluator.displays(in: modelContext)
                routeAggregates = FrequentRouteAggregateService.topAggregates(in: modelContext)
                let pending = achievements.filter(\.needsCelebration)
                if unlockQueue.isEmpty {
                    unlockQueue = pending
                }
                PremiumWidgetBridge.sync(in: modelContext, forecast: builtForecast)
            }
        }
    }

    private func consumeStatsDeepLink() {
        guard let anchor = tabSelection.consumePendingStatsAnchor() else { return }
        switch anchor {
        case .goal:
            break
        case .forecast:
            showForecastDetail = true
        case .recap:
            if recapSnapshot?.hasData == true {
                showRecapStory = true
            }
        case .routes:
            showRoutesMap = true
        case .achievements:
            showAchievements = true
        }
    }

    private func recapSeenKey(for year: Int) -> String {
        "recap.seen.\(year)"
    }

    private func markRecapSeen() {
        let year = Calendar.current.component(.year, from: Date())
        UserDefaults.standard.set(true, forKey: recapSeenKey(for: year))
    }

    private func maybeAutoplayRecap() {
        guard !UITestSupport.isEnabled, !UITestSupport.isUnitTesting else { return }
        let year = Calendar.current.component(.year, from: Date())
        let month = Calendar.current.component(.month, from: Date())
        guard month == 12 || month == 1 else { return }
        guard recapSnapshot?.hasData == true else { return }
        guard !UserDefaults.standard.bool(forKey: recapSeenKey(for: year)) else { return }
        showRecapStory = true
        markRecapSeen()
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
            selectedPlaceName: selectedPlaceName,
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

    private var vehiclePhotoPrefetchID: String {
        VehiclePhotoStore.prefetchTaskID(for: vehicles)
    }

    private var selectedCategoryName: String {
        guard let selectedCategoryID,
              let category = categories.first(where: { $0.storageKey == selectedCategoryID }) else {
            return L10n.all
        }
        return category.name
    }

    private var selectedPlaceDisplayName: String {
        selectedPlaceName ?? L10n.all
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

                    if let selected = vehicles.first(where: { $0.id == selectedVehicleID }) {
                        VehicleAvatarView(
                            systemImage: selected.systemImage,
                            photoFileName: selected.photoFileName,
                            size: 22,
                            cornerRadius: 6,
                            isElectricAccent: selected.fuelType == .electric
                        )
                    }

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

            if !sortedPlaces.isEmpty {
                HStack(spacing: 12) {
                    Text(L10n.filterPlace)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Picker(L10n.filterPlace, selection: $selectedPlaceID) {
                        Text(L10n.all).tag(UUID?.none)
                        ForEach(sortedPlaces, id: \.id) { place in
                            Text(place.name).tag(Optional(place.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(TrailhoundBrandColors.brandBottom)
                    .labelsHidden()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L10n.filterPlace)
                .accessibilityValue(selectedPlaceDisplayName)
            }
        }
        .padding(.vertical, 6)
        .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedPeriod)
        .task(id: vehiclePhotoPrefetchID) {
            await VehiclePhotoStore.shared.prefetch(vehicles: vehicles)
        }
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

    private func summaryMetricsGrid(currencyCode: String) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            summaryMetricCard(
                title: L10n.string("stats.trips"),
                value: "\(snap.stats.tripCount)",
                trend: snap.tripCountTrendText()
            )
            summaryMetricCard(
                title: L10n.string("stats.total_distance"),
                value: snap.stats.totalDistanceText,
                trend: snap.distanceTrendText()
            )
            summaryMetricCard(
                title: L10n.string("stats.total_duration"),
                value: snap.stats.totalDurationText,
                trend: snap.durationTrendText()
            )
            summaryMetricCard(
                title: L10n.string("stats.total_expenses"),
                value: costSnapshot.total > 0
                    ? FuelCostCalculator.formatCost(costSnapshot.total, currencyCode: currencyCode)
                    : "—"
            )
            summaryMetricCard(
                title: L10n.string("stats.average_duration"),
                value: snap.stats.averageDurationText
            )
            summaryMetricCard(
                title: L10n.string("stats.average_speed"),
                value: snap.stats.averageSpeedText,
                trend: snap.averageSpeedTrendText()
            )
            summaryMetricCard(
                title: L10n.string("stats.max_speed"),
                value: snap.stats.maxSpeedText,
                trend: snap.maxSpeedTrendText()
            )
            summaryMetricCard(
                title: L10n.string("stats.cruise_speed"),
                value: snap.stats.cruiseSpeedText,
                trend: snap.cruiseSpeedTrendText(),
                helpTitle: L10n.cruiseSpeedHelpTitle,
                helpBody: L10n.cruiseSpeedHelpBody
            )
            summaryMetricCard(
                title: L10n.string("stats.most_common_speed"),
                value: snap.stats.mostCommonSpeedText,
                trend: snap.mostCommonSpeedTrendText(),
                helpTitle: L10n.mostCommonSpeedHelpTitle,
                helpBody: L10n.mostCommonSpeedHelpBody
            )
            summaryMetricCard(
                title: L10n.string("stats.stop_duration"),
                value: snap.stats.stopDurationText,
                trend: snap.stopDurationTrendText()
            )
            summaryMetricCard(
                title: L10n.string("stats.total_estimated_fuel"),
                value: FuelCostCalculator.formatCost(snap.stats.estimatedFuelCost, currencyCode: currencyCode),
                trend: snap.fuelCostTrendText()
            )
            summaryMetricCard(
                title: L10n.string("stats.total_dynamic_fuel"),
                value: snap.stats.dynamicFuelCost > 0
                    ? FuelCostCalculator.formatCost(snap.stats.dynamicFuelCost, currencyCode: currencyCode)
                    : "—",
                trend: snap.dynamicFuelCostTrendText(),
                helpTitle: L10n.dynamicFuelHelpTitle,
                helpBody: L10n.dynamicFuelHelpBody
            )
            summaryMetricCard(
                title: L10n.string("stats.cost_per_km"),
                value: snap.stats.costPerKm > 0
                    ? FuelCostCalculator.formatCost(snap.stats.costPerKm, currencyCode: currencyCode)
                    : "—"
            )
            summaryMetricCard(
                title: L10n.string("stats.dynamic_cost_per_km"),
                value: snap.stats.dynamicCostPerKm > 0
                    ? FuelCostCalculator.formatCost(snap.stats.dynamicCostPerKm, currencyCode: currencyCode)
                    : "—"
            )
            summaryMetricCard(
                title: L10n.string("stats.average_cost_per_trip"),
                value: snap.stats.averageCostPerTrip > 0
                    ? FuelCostCalculator.formatCost(snap.stats.averageCostPerTrip, currencyCode: currencyCode)
                    : "—"
            )
            summaryMetricCard(
                title: L10n.string("stats.dynamic_cost_per_trip"),
                value: snap.stats.dynamicCostPerTrip > 0
                    ? FuelCostCalculator.formatCost(snap.stats.dynamicCostPerTrip, currencyCode: currencyCode)
                    : "—"
            )
            summaryMetricCard(
                title: L10n.string("stats.night_driving"),
                value: snap.stats.nightDrivingText
            )
        }
    }

    private func summaryMetricCard(
        title: String,
        value: String,
        trend: String? = nil,
        helpTitle: String? = nil,
        helpBody: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .center, spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                if let helpTitle, let helpBody {
                    HelpPopoverButton(
                        accessibilityLabel: helpTitle,
                        message: helpBody,
                        side: 18
                    )
                }
            }
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if let trend {
                Text(trend)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(trendColor(for: trend))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
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
            snap.dailyCruiseSpeed.count,
            snap.dailyMostCommonSpeed.count,
            snap.dailyStopDuration.count,
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

    private enum DailyChartKind: Hashable {
        case distance
        case duration
        case averageSpeed
        case maxSpeed
        case cruiseSpeed
        case mostCommonSpeed
        case stopDuration
        case fuel
        case expenses
    }

    private enum VehicleChartKind: Hashable {
        case distance
        case duration
        case fuel
        case expenses
    }

    private enum CategoryChartKind: Hashable {
        case distance
        case duration
        case fuel
        case expenses
    }

    private var costInterval: DateInterval {
        StatsViewModel.interval(
            for: selectedPeriod,
            customStart: customStart,
            customEnd: customEnd,
            selectedMonth: selectedMonth
        )
    }

    private var dailyChartKinds: [DailyChartKind] {
        var kinds: [DailyChartKind] = []
        if !snap.dailyDistance.isEmpty { kinds.append(.distance) }
        if !snap.dailyDuration.isEmpty { kinds.append(.duration) }
        if !snap.dailyAverageSpeed.isEmpty { kinds.append(.averageSpeed) }
        if !snap.dailyMaxSpeed.isEmpty { kinds.append(.maxSpeed) }
        if !snap.dailyCruiseSpeed.isEmpty { kinds.append(.cruiseSpeed) }
        if !snap.dailyMostCommonSpeed.isEmpty { kinds.append(.mostCommonSpeed) }
        if !snap.dailyStopDuration.isEmpty { kinds.append(.stopDuration) }
        if !snap.dailyFuelCost.isEmpty { kinds.append(.fuel) }
        if costSnapshot.hasTimelineChart { kinds.append(.expenses) }
        return kinds
    }

    private var vehicleChartKinds: [VehicleChartKind] {
        var kinds: [VehicleChartKind] = []
        if snap.showsVehicleBreakdownCharts {
            kinds.append(.distance)
            if !snap.vehicleDuration.isEmpty { kinds.append(.duration) }
            if !snap.vehicleFuelCost.isEmpty { kinds.append(.fuel) }
        }
        if costSnapshot.hasVehicleBreakdown { kinds.append(.expenses) }
        return kinds
    }

    private var categoryChartKinds: [CategoryChartKind] {
        var kinds: [CategoryChartKind] = []
        if !snap.categoryDistance.isEmpty { kinds.append(.distance) }
        if !snap.categoryDuration.isEmpty { kinds.append(.duration) }
        if !snap.categoryFuelCost.isEmpty { kinds.append(.fuel) }
        if costSnapshot.hasCategoryBreakdown { kinds.append(.expenses) }
        return kinds
    }

    @ViewBuilder
    private func dailyChartPageContent(kind: DailyChartKind, pageIndex: Int) -> some View {
        let isActive = pageIndex == dailyChartPage
        let fuelCurrencyCode = settings.fuelCurrency.rawValue
        switch kind {
        case .distance:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.weekly_distance", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyDistanceChartBody(snap.dailyDistance)
            }
        case .duration:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.weekly_duration", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyDurationChartBody(snap.dailyDuration)
            }
        case .averageSpeed:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_average_speed", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyAverageSpeedChartBody(snap.dailyAverageSpeed)
            }
        case .maxSpeed:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_max_speed", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyMaxSpeedChartBody(snap.dailyMaxSpeed)
            }
        case .cruiseSpeed:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_cruise_speed", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyCruiseSpeedChartBody(snap.dailyCruiseSpeed)
            }
        case .mostCommonSpeed:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_most_common_speed", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyMostCommonSpeedChartBody(snap.dailyMostCommonSpeed)
            }
        case .stopDuration:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_stop_duration", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                dailyStopDurationChartBody(snap.dailyStopDuration)
            }
        case .fuel:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_fuel", scope: statsTripChartScopeLabel),
                chartHeight: 200,
                reduceMotion: reduceMotion,
                isPageActive: isActive,
                titleAccessory: {
                    HelpPopoverButton(
                        accessibilityLabel: L10n.dynamicFuelHelpTitle,
                        message: L10n.dynamicFuelHelpBody
                    )
                }
            ) {
                dailyFuelCostChartBody(snap.dailyFuelCost)
            }
        case .expenses:
            StatsDeferredChart(
                title: titledWithScope("stats.chart.daily_expenses", scope: statsTripChartScopeLabel),
                chartHeight: StatsChartTheme.costBarChartBodyHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                VehicleCareMiniChart(
                    months: costSnapshot.months,
                    days: costSnapshot.days,
                    periodStart: costInterval.start,
                    periodEnd: costInterval.end,
                    currencyCode: fuelCurrencyCode
                )
            }
        }
    }

    @ViewBuilder
    private func vehicleChartPageContent(kind: VehicleChartKind, pageIndex: Int) -> some View {
        let isActive = pageIndex == vehicleChartPage
        switch kind {
        case .distance:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                vehicleDistanceDonut(data: snap.vehicleDistance)
            }
        case .duration:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                vehicleDurationDonut(data: snap.vehicleDuration)
            }
        case .fuel:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                vehicleFuelDonut(data: snap.vehicleFuelCost)
            }
        case .expenses:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                vehicleExpensesDonut(data: costSnapshot.vehicleBreakdown)
            }
        }
    }

    @ViewBuilder
    private func categoryChartPageContent(kind: CategoryChartKind, pageIndex: Int) -> some View {
        let isActive = pageIndex == categoryChartPage
        switch kind {
        case .distance:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                categoryDistanceDonut(data: snap.categoryDistance)
            }
        case .duration:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                categoryDurationDonut(data: snap.categoryDuration)
            }
        case .fuel:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                categoryFuelDonut(data: snap.categoryFuelCost)
            }
        case .expenses:
            StatsDeferredContent(
                placeholderHeight: StatsChartPagerMetrics.donutContentHeight,
                reduceMotion: reduceMotion,
                isPageActive: isActive
            ) {
                categoryExpensesDonut(data: costSnapshot.categoryBreakdown)
            }
        }
    }

    @ViewBuilder
    private func dailyBarValueLabel(text: String?, barCount: Int) -> some View {
        if let text {
            StatsBarValueLabel(text: text, barCount: barCount)
        }
    }

    private func dailyDistanceBarText(_ meters: Double, barCount: Int) -> String? {
        guard meters > 0 else { return nil }
        if barCount <= 8 {
            return DateFormatters.formatDistance(meters)
        }
        let kilometers = meters / 1000
        return kilometers >= 10
            ? String(format: "%.0f", kilometers)
            : String(format: "%.1f", kilometers)
    }

    private func dailySpeedBarText(_ kmh: Double, barCount: Int) -> String? {
        guard kmh > 0 else { return nil }
        if barCount <= 8 {
            return L10n.formatSpeedKmh(kmh)
        }
        return String(format: "%.0f", kmh)
    }

    private func dailyDistanceChartBody(_ dailyChartData: [DailyDistance]) -> some View {
        let days = dailyChartData.map(\.day)
        let barCount = dailyChartData.count
        return Chart(dailyChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.distance_km"), item.distanceKilometers)
            )
            .foregroundStyle(StatsChartTheme.distanceBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
            .annotation(position: .top, spacing: 2) {
                dailyBarValueLabel(
                    text: dailyDistanceBarText(item.distanceMeters, barCount: barCount),
                    barCount: barCount
                )
            }
        }
        .chartBarValueHeadroom(maxValue: dailyChartData.map(\.distanceKilometers).max() ?? 0)
        .chartStatsYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.distance_km"))
        .frame(height: 200)
    }

    private func dailyDurationChartBody(_ dailyDurationChartData: [DailyDuration]) -> some View {
        let days = dailyDurationChartData.map(\.day)
        let barCount = dailyDurationChartData.count
        return Chart(dailyDurationChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.duration_hours"), item.durationHours)
            )
            .foregroundStyle(StatsChartTheme.durationBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
            .annotation(position: .top, spacing: 2) {
                dailyBarValueLabel(
                    text: item.duration > 0 ? DateFormatters.formatDuration(item.duration) : nil,
                    barCount: barCount
                )
            }
        }
        .chartBarValueHeadroom(maxValue: dailyDurationChartData.map(\.durationHours).max() ?? 0)
        .chartStatsYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.duration_hours"))
        .frame(height: 200)
    }

    private func dailyAverageSpeedChartBody(_ dailyAverageSpeedChartData: [DailyAverageSpeed]) -> some View {
        let days = dailyAverageSpeedChartData.map(\.day)
        let barCount = dailyAverageSpeedChartData.count
        return Chart(dailyAverageSpeedChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.speed_kmh"), item.speedKmh)
            )
            .foregroundStyle(StatsChartTheme.averageSpeedBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
            .annotation(position: .top, spacing: 2) {
                dailyBarValueLabel(
                    text: dailySpeedBarText(item.speedKmh, barCount: barCount),
                    barCount: barCount
                )
            }
        }
        .chartBarValueHeadroom(maxValue: dailyAverageSpeedChartData.map(\.speedKmh).max() ?? 0)
        .chartStatsYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.speed_kmh"))
        .frame(height: 200)
    }

    private func dailyMaxSpeedChartBody(_ dailyMaxSpeedChartData: [DailyMaxSpeed]) -> some View {
        let days = dailyMaxSpeedChartData.map(\.day)
        let barCount = dailyMaxSpeedChartData.count
        return Chart(dailyMaxSpeedChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.speed_kmh"), item.speedKmh)
            )
            .foregroundStyle(StatsChartTheme.maxSpeedBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
            .annotation(position: .top, spacing: 2) {
                dailyBarValueLabel(
                    text: dailySpeedBarText(item.speedKmh, barCount: barCount),
                    barCount: barCount
                )
            }
        }
        .chartBarValueHeadroom(maxValue: dailyMaxSpeedChartData.map(\.speedKmh).max() ?? 0)
        .chartStatsYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.speed_kmh"))
        .frame(height: 200)
    }

    private func dailyCruiseSpeedChartBody(_ dailyCruiseSpeedChartData: [DailyCruiseSpeed]) -> some View {
        let days = dailyCruiseSpeedChartData.map(\.day)
        let barCount = dailyCruiseSpeedChartData.count
        return Chart(dailyCruiseSpeedChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.speed_kmh"), item.speedKmh)
            )
            .foregroundStyle(StatsChartTheme.cruiseSpeedBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
            .annotation(position: .top, spacing: 2) {
                dailyBarValueLabel(
                    text: dailySpeedBarText(item.speedKmh, barCount: barCount),
                    barCount: barCount
                )
            }
        }
        .chartBarValueHeadroom(maxValue: dailyCruiseSpeedChartData.map(\.speedKmh).max() ?? 0)
        .chartStatsYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.speed_kmh"))
        .frame(height: 200)
    }

    private func dailyMostCommonSpeedChartBody(_ dailyMostCommonSpeedChartData: [DailyMostCommonSpeed]) -> some View {
        let days = dailyMostCommonSpeedChartData.map(\.day)
        let barCount = dailyMostCommonSpeedChartData.count
        return Chart(dailyMostCommonSpeedChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.speed_kmh"), item.speedKmh)
            )
            .foregroundStyle(StatsChartTheme.mostCommonSpeedBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
            .annotation(position: .top, spacing: 2) {
                dailyBarValueLabel(
                    text: dailySpeedBarText(item.speedKmh, barCount: barCount),
                    barCount: barCount
                )
            }
        }
        .chartBarValueHeadroom(maxValue: dailyMostCommonSpeedChartData.map(\.speedKmh).max() ?? 0)
        .chartStatsYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.speed_kmh"))
        .frame(height: 200)
    }

    private func dailyStopDurationChartBody(_ dailyStopDurationChartData: [DailyStopDuration]) -> some View {
        let days = dailyStopDurationChartData.map(\.day)
        let barCount = dailyStopDurationChartData.count
        return Chart(dailyStopDurationChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.duration_hours"), item.durationHours)
            )
            .foregroundStyle(StatsChartTheme.stopDurationBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
            .annotation(position: .top, spacing: 2) {
                dailyBarValueLabel(
                    text: item.duration > 0 ? DateFormatters.formatDuration(item.duration) : nil,
                    barCount: barCount
                )
            }
        }
        .chartBarValueHeadroom(maxValue: dailyStopDurationChartData.map(\.durationHours).max() ?? 0)
        .chartStatsYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.duration_hours"))
        .frame(height: 200)
    }

    private func dailyFuelCostChartBody(_ dailyFuelCostChartData: [DailyFuelCost]) -> some View {
        let days = dailyFuelCostChartData.map(\.day)
        let barCount = dailyFuelCostChartData.count
        let showValueLabels = barCount <= 10
        let avgLabel = L10n.string("stats.chart.fuel_avg")
        let estLabel = L10n.string("stats.chart.fuel_estimated")
        let avgColor = Color(red: 0.28, green: 0.78, blue: 0.86)
        let estColor = Color(red: 0.98, green: 0.58, blue: 0.24)
        let maxValue = dailyFuelCostChartData.map { max($0.cost, $0.dynamicCost) }.max() ?? 0

        return Chart {
            ForEach(dailyFuelCostChartData) { item in
                let hostOnAvg = item.cost >= item.dynamicCost
                BarMark(
                    x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                    y: .value(L10n.string("stats.chart.fuel_cost"), item.cost)
                )
                .foregroundStyle(by: .value("series", avgLabel))
                .position(by: .value("series", avgLabel))
                .cornerRadius(StatsChartTheme.barCornerRadius)
                .annotation(position: .top, spacing: 2) {
                    if showValueLabels, hostOnAvg {
                        dailyFuelDualValueLabel(
                            avg: item.cost,
                            estimated: item.dynamicCost,
                            avgColor: avgColor,
                            estColor: estColor,
                            barCount: barCount
                        )
                    }
                }

                BarMark(
                    x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                    y: .value(L10n.string("stats.chart.fuel_cost"), item.dynamicCost)
                )
                .foregroundStyle(by: .value("series", estLabel))
                .position(by: .value("series", estLabel))
                .cornerRadius(StatsChartTheme.barCornerRadius)
                .annotation(position: .top, spacing: 2) {
                    if showValueLabels, !hostOnAvg {
                        dailyFuelDualValueLabel(
                            avg: item.cost,
                            estimated: item.dynamicCost,
                            avgColor: avgColor,
                            estColor: estColor,
                            barCount: barCount
                        )
                    }
                }
            }
        }
        .chartForegroundStyleScale([
            avgLabel: avgColor,
            estLabel: estColor
        ])
        .chartLegend(position: .bottom, alignment: .leading)
        // Extra headroom for the two-line stacked label.
        .chartYScale(domain: [0, max(maxValue * 1.42, 1)])
        .chartStatsYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.fuel_cost"))
        .frame(height: 200)
    }

    /// Compact dual label (no currency symbol) so Avg + Est. stay readable above grouped bars.
    @ViewBuilder
    private func dailyFuelDualValueLabel(
        avg: Double,
        estimated: Double,
        avgColor: Color,
        estColor: Color,
        barCount: Int
    ) -> some View {
        // Dual stack needs smaller type than single-series bars.
        let font = StatsChartTheme.barValueLabelFont(barCount: max(barCount + 6, 14))
        VStack(spacing: 0) {
            if avg > 0 {
                Text(compactFuelBarAmount(avg))
                    .font(font)
                    .foregroundStyle(avgColor)
            }
            if estimated > 0 {
                Text(compactFuelBarAmount(estimated))
                    .font(font)
                    .foregroundStyle(estColor)
            }
        }
        .monospacedDigit()
        .allowsTightening(true)
    }

    private func compactFuelBarAmount(_ amount: Double) -> String {
        String(format: "%.0f", amount.rounded())
    }

    private func statsDonutLegendItem(
        id: String,
        name: String,
        durationStyle: Bool,
        domainKeys: [String],
        value: String
    ) -> StatsDonutLegendItem {
        StatsDonutLegendItem(
            id: id,
            name: name,
            color: StatsChartTheme.sliceColor(
                forStableKey: id,
                durationStyle: durationStyle,
                domainKeys: domainKeys
            ),
            value: value
        )
    }

    private func chartSlicePalette(
        labels: [String],
        stableKeys: [String],
        durationStyle: Bool
    ) -> ([String], [Color]) {
        StatsChartTheme.sliceScale(labels: labels, stableKeys: stableKeys, durationStyle: durationStyle)
    }

    private static let donutChartHeight: CGFloat = 150

    @ViewBuilder
    private func statsDonutPage<ChartContent: View>(
        titleKey: StaticString,
        centerTotal: String,
        legendItems: [StatsDonutLegendItem],
        @ViewBuilder chart: () -> ChartContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titledWithScope(titleKey, scope: statsTripChartScopeLabel))
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: StatsChartTheme.donutLegendTopPadding) {
                ZStack {
                    chart()
                        .frame(maxWidth: .infinity)
                        .statsHiddenDonutLegend(height: Self.donutChartHeight)

                    VStack(spacing: 2) {
                        Text(centerTotal)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                            .lineLimit(2)
                        Text(L10n.string("stats.cost.chart.center_total"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .allowsHitTesting(false)
                }

                StatsDonutLegendGrid(items: legendItems)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        // Keep content above the pager clip / page dots.
        .padding(.bottom, 2)
    }

    private func vehicleDistanceDonut(data vehicleChartData: [VehicleDistance]) -> some View {
        let names = vehicleChartData.map(\.name)
        let keys = vehicleChartData.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let totalMeters = vehicleChartData.reduce(0) { $0 + $1.distanceMeters }
        let legendItems = vehicleChartData.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: false,
                domainKeys: keys,
                value: DateFormatters.formatDistance(item.distanceMeters)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.vehicles",
            centerTotal: DateFormatters.formatDistance(totalMeters),
            legendItems: legendItems
        ) {
            Chart(vehicleChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.distance_km"), item.distanceKilometers),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.vehicle"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func vehicleDurationDonut(data vehicleDurationChartData: [VehicleDuration]) -> some View {
        let names = vehicleDurationChartData.map(\.name)
        let keys = vehicleDurationChartData.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: true)
        let totalDuration = vehicleDurationChartData.reduce(0) { $0 + $1.duration }
        let legendItems = vehicleDurationChartData.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: true,
                domainKeys: keys,
                value: DateFormatters.formatDuration(item.duration)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.vehicles_duration",
            centerTotal: DateFormatters.formatDuration(totalDuration),
            legendItems: legendItems
        ) {
            Chart(vehicleDurationChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.duration_hours"), item.durationHours),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.vehicle"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func categoryDistanceDonut(data categoryChartData: [CategoryDistance]) -> some View {
        let names = categoryChartData.map(\.name)
        let keys = categoryChartData.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let totalMeters = categoryChartData.reduce(0) { $0 + $1.distanceMeters }
        let legendItems = categoryChartData.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: false,
                domainKeys: keys,
                value: DateFormatters.formatDistance(item.distanceMeters)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.categories",
            centerTotal: DateFormatters.formatDistance(totalMeters),
            legendItems: legendItems
        ) {
            Chart(categoryChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.distance_km"), item.distanceKilometers),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.category"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func categoryDurationDonut(data categoryDurationChartData: [CategoryDuration]) -> some View {
        let names = categoryDurationChartData.map(\.name)
        let keys = categoryDurationChartData.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: true)
        let totalDuration = categoryDurationChartData.reduce(0) { $0 + $1.duration }
        let legendItems = categoryDurationChartData.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: true,
                domainKeys: keys,
                value: DateFormatters.formatDuration(item.duration)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.categories_duration",
            centerTotal: DateFormatters.formatDuration(totalDuration),
            legendItems: legendItems
        ) {
            Chart(categoryDurationChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.duration_hours"), item.durationHours),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.category"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func vehicleFuelDonut(data vehicleFuelChartData: [VehicleFuelCost]) -> some View {
        let names = vehicleFuelChartData.map(\.name)
        let keys = vehicleFuelChartData.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let currency = AppSettings.shared.fuelCurrency.rawValue
        let totalCost = vehicleFuelChartData.reduce(0) { $0 + $1.cost }
        let legendItems = vehicleFuelChartData.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: false,
                domainKeys: keys,
                value: FuelCostCalculator.formatCost(item.cost, currencyCode: currency)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.vehicles_fuel",
            centerTotal: FuelCostCalculator.formatCost(totalCost, currencyCode: currency),
            legendItems: legendItems
        ) {
            Chart(vehicleFuelChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.fuel_cost"), item.cost),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.vehicle"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func categoryFuelDonut(data categoryFuelChartData: [CategoryFuelCost]) -> some View {
        let names = categoryFuelChartData.map(\.name)
        let keys = categoryFuelChartData.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let currency = AppSettings.shared.fuelCurrency.rawValue
        let totalCost = categoryFuelChartData.reduce(0) { $0 + $1.cost }
        let legendItems = categoryFuelChartData.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.name,
                durationStyle: false,
                domainKeys: keys,
                value: FuelCostCalculator.formatCost(item.cost, currencyCode: currency)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.categories_fuel",
            centerTotal: FuelCostCalculator.formatCost(totalCost, currencyCode: currency),
            legendItems: legendItems
        ) {
            Chart(categoryFuelChartData) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.fuel_cost"), item.cost),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.category"), item.name))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func vehicleExpensesDonut(data shares: [VehicleExpenseShare]) -> some View {
        let items = shares.filter { $0.amount > 0 }
        let names = items.map(\.displayName)
        let keys = items.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let currency = AppSettings.shared.fuelCurrency.rawValue
        let totalAmount = items.reduce(0) { $0 + $1.amount }
        let legendItems = items.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.displayName,
                durationStyle: false,
                domainKeys: keys,
                value: FuelCostCalculator.formatCost(item.amount, currencyCode: currency)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.vehicles_expenses",
            centerTotal: FuelCostCalculator.formatCost(totalAmount, currencyCode: currency),
            legendItems: legendItems
        ) {
            Chart(items) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.daily_expenses"), item.amount),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.vehicle"), item.displayName))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }

    private func categoryExpensesDonut(data breakdown: [VehicleCategoryCost]) -> some View {
        let items = breakdown.filter { $0.amount > 0 }
        let names = items.map(\.displayName)
        let keys = items.map(\.id)
        let palette = chartSlicePalette(labels: names, stableKeys: keys, durationStyle: false)
        let currency = AppSettings.shared.fuelCurrency.rawValue
        let totalAmount = items.reduce(0) { $0 + $1.amount }
        let legendItems = items.map { item in
            statsDonutLegendItem(
                id: item.id,
                name: item.displayName,
                durationStyle: false,
                domainKeys: keys,
                value: FuelCostCalculator.formatCost(item.amount, currencyCode: currency)
            )
        }
        return statsDonutPage(
            titleKey: "stats.chart.categories_expenses",
            centerTotal: FuelCostCalculator.formatCost(totalAmount, currencyCode: currency),
            legendItems: legendItems
        ) {
            Chart(items) { item in
                SectorMark(
                    angle: .value(L10n.string("stats.chart.daily_expenses"), item.amount),
                    innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                    angularInset: StatsChartTheme.donutAngularInset
                )
                .foregroundStyle(by: .value(L10n.string("filter.category"), item.displayName))
            }
            .chartForegroundStyleScale(domain: palette.0, range: palette.1)
        }
    }
}

private struct StatsSnapshotInputs: Equatable {
    let storeVersion: Int
    let categoryCount: Int
    let vehicleCount: Int
    let placeCount: Int
    let period: StatsPeriod
    let customStart: Date
    let customEnd: Date
    let selectedMonth: Date
    let selectedCategoryID: String?
    let selectedVehicleID: UUID?
    let selectedPlaceID: UUID?
    let selectedPlaceName: String?
}

private enum StatsChartPairTokens {
    static let cardSpacing: CGFloat = 12
    static let cardContentInset: CGFloat = 14
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

    /// Compact glass rows for the Stats summary / period-total strip.
    func statsSummaryGlassRow(_ position: GlassRowPosition) -> some View {
        let horizontal = GlassTokens.listContentHorizontalInset
        let insets: EdgeInsets
        switch position {
        case .only:
            insets = EdgeInsets(top: 8, leading: horizontal, bottom: 8, trailing: horizontal)
        case .first:
            insets = EdgeInsets(top: 8, leading: horizontal, bottom: 3, trailing: horizontal)
        case .middle:
            insets = EdgeInsets(top: 3, leading: horizontal, bottom: 3, trailing: horizontal)
        case .last:
            insets = EdgeInsets(top: 3, leading: horizontal, bottom: 8, trailing: horizontal)
        }
        return glassRow(position: position)
            .listRowInsets(insets)
    }
}

#Preview {
    NavigationStack { StatsView() }
        .modelContainer(PreviewData.shared.container)
}
