import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    // Deliberately no `@Query` for trips: the stats tab only ever aggregates the selected period,
    // so it fetches that window instead of pulling the whole library into memory.
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Query private var vehicles: [VehicleProfile]
    @Query private var places: [SavedPlace]
    @Query(sort: \TravelJournal.endedOn, order: .reverse) private var journals: [TravelJournal]
    @Environment(\.modelContext) private var modelContext
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedPeriod: StatsPeriod = .week
    @State private var selectedCategoryID: String?
    @State private var selectedVehicleID: UUID?
    @State private var selectedPlaceID: UUID?
    @State private var selectedJournalID: UUID?
    @State private var selectedMonth = StatsFilterDefaults.selectedMonth()
    @State private var customStart = StatsFilterDefaults.customStart()
    @State private var customEnd = Date()
    @State private var animatedProgress: Double = 0
    @State private var snapshot: StatsDisplaySnapshot?
    @State private var renderedSnapshotFingerprint: String?
    @State private var snapshotRefreshTask: Task<Void, Never>?
    @State private var earliestTripStart: Date?
    /// Bumped whenever the store reports a save, standing in for the change tracking a `@Query`
    /// would have given us.
    @State private var storeVersion = 0
    @State private var snapshotLoader: StatsSnapshotLoader?
    @State private var costSnapshotLoader: VehicleCostSnapshotLoader?
    @State private var costSnapshot: VehicleCostSnapshot = .empty
    @State private var costRefreshTask: Task<Void, Never>?
    @State private var yearAwardsLoader: StatsYearAwardsLoader?
    @State private var yearAwards: StatsYearAwardsSnapshot?
    @State private var selectedAwardsYear = Calendar.current.component(.year, from: Date())
    @State private var yearAwardsRefreshTask: Task<Void, Never>?
    @State private var yearAwardsSectionAppeared = false
    @State private var hasCompletedInitialSnapshot = false
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
            journalCount: journals.count,
            period: selectedPeriod,
            customStart: customStart,
            customEnd: customEnd,
            selectedMonth: selectedMonth,
            selectedCategoryID: selectedCategoryID,
            selectedVehicleID: selectedVehicleID,
            selectedPlaceID: selectedPlaceID,
            selectedPlaceName: selectedPlaceName,
            selectedJournalID: selectedJournalID
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
        if selectedJournalID != nil {
            parts.append(selectedJournalName)
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
            selectedPlaceName ?? "",
            selectedJournalID?.uuidString ?? ""
        ].joined(separator: "|")
    }

    private var showsSummarySkeleton: Bool {
        snapshot == nil || renderedSnapshotFingerprint != statsFilterFingerprint
    }

    private var activeStatsFilterCount: Int {
        var count = 0
        if selectedPeriod != .week { count += 1 }
        if selectedCategoryID != nil { count += 1 }
        if selectedVehicleID != nil { count += 1 }
        if selectedPlaceID != nil { count += 1 }
        if selectedJournalID != nil { count += 1 }
        return count
    }

    private var hasResettableStatsFilters: Bool {
        activeStatsFilterCount > 0
    }

    private var statsFilterMenuColumns: [GridItem] {
        let spacing: CGFloat = 8
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: spacing)]
        }
        return [
            GridItem(.flexible(), spacing: spacing),
            GridItem(.flexible(), spacing: spacing)
        ]
    }

    private func titledWithScope(_ baseKey: StaticString, scope: String) -> String {
        String(format: L10n.string("stats.title.with_scope"), L10n.string(baseKey), scope)
    }

    var body: some View {
        let fuelCurrencyCode = settings.fuelCurrency.rawValue
        List {
            Section(L10n.string("filter.title")) {
                statsFilterCard
                    .statsFullCard()
            }

            Section {
                StatsCardPair {
                    statsGoalCard
                } right: {
                    statsHeroCard(currencyCode: fuelCurrencyCode)
                }
            }

            Section(titledWithScope("stats.summary.section", scope: statsSummaryScopeLabel)) {
                summaryMetricsGrid(currencyCode: fuelCurrencyCode)
                    .statsFullCard(contentInset: StatsCardTokens.summaryGridInset)
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
                    .statsFullCard()
                }
                .id("daily-\(statsFilterFingerprint)")
                .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedPeriod)
            }

            if showsVehicleCompareList {
                Section {
                    StatsVehicleCompareList(
                        rows: vehicleCompareRows,
                        currencyCode: fuelCurrencyCode
                    )
                    .statsFullCard()
                }
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
                    .statsFullCard()
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
                    .statsFullCard()
                }
                .id("categories-\(statsFilterFingerprint)")
                .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedCategoryID)
            }

            Section {
                StatsYearAwardsCard(
                    snapshot: yearAwards,
                    medals: yearAwardsMedals,
                    years: awardsYears,
                    selectedYear: $selectedAwardsYear,
                    reduceMotion: reduceMotion,
                    onAppear: {
                        yearAwardsSectionAppeared = true
                        scheduleYearAwardsRefresh(delayMilliseconds: 0)
                    }
                )
                .statsFullCard()
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
            refreshEarliestTripStart()
            normalizeSelectedMonth()
            updateAnimatedProgress(animated: false)
            scheduleSnapshotRefresh()
            scheduleCostSnapshotRefresh()
        }
        .onStoreSave {
            refreshEarliestTripStart()
            storeVersion &+= 1
            if hasCompletedInitialSnapshot {
                scheduleYearAwardsRefresh(
                    delayMilliseconds: yearAwardsSectionAppeared ? 0 : 300
                )
            }
        }
        .onChange(of: snapshotInputs) { _, _ in
            scheduleSnapshotRefresh()
            scheduleCostSnapshotRefresh()
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
        .onChange(of: selectedJournalID) { _, _ in
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
        .onChange(of: selectedAwardsYear) { _, _ in
            scheduleYearAwardsRefresh(delayMilliseconds: 0)
        }
        .onChange(of: earliestTripStart) { _, _ in
            clampSelectedAwardsYear()
        }
        .onDisappear {
            snapshotRefreshTask?.cancel()
            yearAwardsRefreshTask?.cancel()
            costRefreshTask?.cancel()
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
        let previous = StatsViewModel.alignedPreviousInterval(
            for: selectedPeriod,
            selectedInterval: interval,
            selectedMonth: selectedMonth
        )
        let request = VehicleCostSnapshotRequest(
            storeVersion: storeVersion,
            periodStart: interval.start,
            periodEnd: interval.end,
            selectedVehicleID: selectedVehicleID,
            compareStart: previous.start,
            compareEnd: previous.end
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
            selectedJournalID: selectedJournalID,
            categoryNames: StatsViewModel.categoryNameMap(for: categories),
            vehicleNames: StatsViewModel.vehicleNameMap(for: vehicles),
            vehicleCount: vehicles.count
        )

        let requestFingerprint = statsFilterFingerprint
        snapshotRefreshTask = Task {
            if !isFirstLoad {
                try? await Task.sleep(for: .milliseconds(120))
            }
            guard !Task.isCancelled else { return }
            let built = await loader.snapshot(for: request)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                snapshot = built
                renderedSnapshotFingerprint = requestFingerprint
                if !hasCompletedInitialSnapshot {
                    hasCompletedInitialSnapshot = true
                    scheduleYearAwardsRefresh(
                        delayMilliseconds: yearAwardsSectionAppeared ? 0 : 300
                    )
                }
            }
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
        selectedVehicle?.name ?? L10n.all
    }

    private var selectedVehicle: VehicleProfile? {
        guard let selectedVehicleID else { return nil }
        return vehicles.first(where: { $0.id == selectedVehicleID })
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

    private var selectedJournalName: String {
        guard let selectedJournalID,
              let journal = journals.first(where: { $0.id == selectedJournalID }) else {
            return L10n.all
        }
        return journal.title
    }

    private var statsFilterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasResettableStatsFilters {
                statsFilterHeader
                    .transition(reduceMotion ? .identity : .opacity)
            }

            statsPeriodChipRow

            if selectedPeriod == .month {
                statsMonthPicker
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }

            if selectedPeriod == .custom {
                statsCustomDateFields
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }

            LazyVGrid(columns: statsFilterMenuColumns, alignment: .leading, spacing: 8) {
                StatsFilterMenuField(
                    title: L10n.string("filter.category"),
                    value: selectedCategoryName,
                    isActive: selectedCategoryID != nil,
                    identifier: "stats.filters.category"
                ) {
                    Picker(L10n.string("filter.category"), selection: $selectedCategoryID) {
                        Text(L10n.all).tag(String?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.storageKey))
                        }
                    }
                    .pickerStyle(.inline)
                }

                if !vehicles.isEmpty {
                    StatsFilterMenuField(
                        title: L10n.string("filter.vehicle"),
                        value: selectedVehicleName,
                        isActive: selectedVehicleID != nil,
                        identifier: "stats.filters.vehicle",
                        avatarSystemImage: selectedVehicle?.systemImage,
                        avatarPhotoFileName: selectedVehicle?.photoFileName,
                        avatarIsElectric: selectedVehicle?.fuelType == .electric
                    ) {
                        Picker(L10n.string("filter.vehicle"), selection: $selectedVehicleID) {
                            Text(L10n.all).tag(UUID?.none)
                            ForEach(vehicles) { vehicle in
                                Text(vehicle.name).tag(Optional(vehicle.id))
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }

                if !sortedPlaces.isEmpty {
                    StatsFilterMenuField(
                        title: L10n.filterPlace,
                        value: selectedPlaceDisplayName,
                        isActive: selectedPlaceID != nil,
                        identifier: "stats.filters.place"
                    ) {
                        Picker(L10n.filterPlace, selection: $selectedPlaceID) {
                            Text(L10n.all).tag(UUID?.none)
                            ForEach(sortedPlaces, id: \.id) { place in
                                Text(place.name).tag(Optional(place.id))
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }

                if !journals.isEmpty {
                    StatsFilterMenuField(
                        title: L10n.journalStatsFilter,
                        value: selectedJournalName,
                        isActive: selectedJournalID != nil,
                        identifier: "stats.filters.journal"
                    ) {
                        Picker(L10n.journalStatsFilter, selection: $selectedJournalID) {
                            Text(L10n.all).tag(UUID?.none)
                            ForEach(journals, id: \.id) { journal in
                                Text(journal.title).tag(Optional(journal.id))
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }
        }
        .accessibilityIdentifier("stats.filters.card")
        .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedPeriod)
        .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: hasResettableStatsFilters)
        .task(id: vehiclePhotoPrefetchID) {
            await VehiclePhotoStore.shared.prefetch(vehicles: vehicles)
        }
    }

    private var statsFilterHeader: some View {
        HStack(spacing: 8) {
            Text("\(activeStatsFilterCount)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, 4)
                .background(TrailhoundBrandColors.brandBottom, in: Capsule())
                .accessibilityHidden(true)

            Text(L10n.statsFiltersActiveCount(activeStatsFilterCount))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                resetStatsFiltersToDefaults()
            } label: {
                Text(L10n.statsFiltersClear)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TrailhoundBrandColors.brandBottom)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 28)
                    .glassField(cornerRadius: 10)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stats.filters.clear")
        }
        .accessibilityElement(children: .contain)
    }

    private var statsPeriodChipRow: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    statsPeriodChips
                }
            } else {
                HStack(spacing: 6) {
                    statsPeriodChips
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.string("stats.period.title"))
    }

    private var statsPeriodChips: some View {
        ForEach(StatsPeriod.allCases) { period in
            GlassFilterChip(
                title: period.title,
                isSelected: selectedPeriod == period,
                namespace: periodChipNamespace,
                highlightID: "statsPeriodHighlight",
                expands: true,
                size: .compact
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
            .accessibilityIdentifier("stats.filters.period.\(period.rawValue)")
        }
    }

    private var statsCustomDateFields: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    statsCustomDateField(
                        title: L10n.string("stats.period.start"),
                        date: $customStart
                    )
                    statsCustomDateField(
                        title: L10n.string("stats.period.end"),
                        date: $customEnd
                    )
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    statsCustomDateField(
                        title: L10n.string("stats.period.start"),
                        date: $customStart
                    )
                    statsCustomDateField(
                        title: L10n.string("stats.period.end"),
                        date: $customEnd
                    )
                }
            }
        }
    }

    private func resetStatsFiltersToDefaults() {
        let reset = {
            selectedPeriod = .week
            selectedCategoryID = nil
            selectedVehicleID = nil
            selectedPlaceID = nil
            selectedJournalID = nil
            selectedMonth = StatsFilterDefaults.selectedMonth()
            customStart = StatsFilterDefaults.customStart()
            customEnd = Date()
        }
        TrailhoundHaptics.selection()
        if reduceMotion {
            reset()
        } else {
            withAnimation(TrailhoundMotion.gentle) {
                reset()
            }
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
        HStack(spacing: 0) {
            monthStepButton(
                systemImage: "chevron.left",
                enabled: canGoToPreviousMonth,
                accessibilityKey: "stats.period.previous_month"
            ) {
                shiftSelectedMonth(by: -1)
            }

            Menu {
                Picker(L10n.string("stats.period.select_month"), selection: selectedMonthBinding) {
                    ForEach(selectableMonths, id: \.self) { month in
                        Text(DateFormatters.monthYear.string(from: month))
                            .tag(month)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 5) {
                    Text(selectedMonthTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(TrailhoundBrandColors.brandBottom)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.string("stats.period.select_month"))
            .accessibilityValue(selectedMonthTitle)

            monthStepButton(
                systemImage: "chevron.right",
                enabled: canGoToNextMonth,
                accessibilityKey: "stats.period.next_month"
            ) {
                shiftSelectedMonth(by: 1)
            }
        }
        .padding(.horizontal, 4)
        .glassField(cornerRadius: 12)
        .onAppear {
            selectedMonth = StatsViewModel.clampedMonth(
                selectedMonth,
                earliestTripStart: earliestTripStart
            )
        }
    }

    private func shiftSelectedMonth(by value: Int) {
        selectedMonth = StatsViewModel.clampedMonth(
            StatsViewModel.shiftMonth(selectedMonth, by: value),
            earliestTripStart: earliestTripStart
        )
        TrailhoundHaptics.selection()
    }

    private func monthStepButton(
        systemImage: String,
        enabled: Bool,
        accessibilityKey: StaticString,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(enabled ? Color.primary : Color.primary.opacity(0.28))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(L10n.string(accessibilityKey))
    }

    private func statsCustomDateField(title: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            DatePicker(title, selection: date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .glassField(cornerRadius: 12)
    }

    private var statsGoalCard: some View {
        VStack(spacing: 8) {
            goalRing
            VStack(spacing: 2) {
                Text(L10n.string("stats.goal.monthly"))
                    .font(.caption.weight(.semibold))
                Text(goalRangeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("\(DateFormatters.formatDistance(snap.goalDistanceMeters)) / \(DateFormatters.formatDistance(goalTargetMeters))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .multilineTextAlignment(.center)

            if isGoalEditable {
                VStack(spacing: 4) {
                    Text(L10n.string("stats.goal.target_km"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    statsGoalStepper
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var statsGoalStepper: some View {
        let kilometers = Int(goalTargetMeters / 1000)
        let minimum = 50
        let maximum = 2000
        let step = 50
        return HStack(spacing: 0) {
            Button {
                guard kilometers > minimum else { return }
                settings.setMonthlyGoalMeters(Double(kilometers - step) * 1000)
                TrailhoundHaptics.selection()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .disabled(kilometers <= minimum)

            Rectangle()
                .fill(Color.primary.opacity(0.2))
                .frame(width: 0.5, height: 12)

            Button {
                guard kilometers < maximum else { return }
                settings.setMonthlyGoalMeters(Double(kilometers + step) * 1000)
                TrailhoundHaptics.selection()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .disabled(kilometers >= maximum)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .glassField(cornerRadius: 12)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.string("stats.goal.target_km"))
        .accessibilityValue(DateFormatters.formatDistance(goalTargetMeters))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                guard kilometers < maximum else { return }
                settings.setMonthlyGoalMeters(Double(kilometers + step) * 1000)
            case .decrement:
                guard kilometers > minimum else { return }
                settings.setMonthlyGoalMeters(Double(kilometers - step) * 1000)
            @unknown default:
                break
            }
            TrailhoundHaptics.selection()
        }
    }

    private func statsHeroCard(currencyCode: String) -> some View {
        let rows = heroCompareRows(currencyCode: currencyCode)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(row.currentText)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        StatsTrendBadge(trend: row.trend, metricName: row.title)
                    }
                    Text("\(comparePreviousLabel) \(row.previousText)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(heroAccessibilityLabel(for: row))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func heroAccessibilityLabel(for row: StatsPeriodCompareRow) -> String {
        var parts = [
            row.title,
            "\(compareCurrentLabel) \(row.currentText)",
            "\(comparePreviousLabel) \(row.previousText)"
        ]
        if let trend = row.trend {
            parts.append(trend.accessibilityLabel(metricName: row.title))
        }
        return parts.joined(separator: ", ")
    }

    private func heroCompareRows(currencyCode: String) -> [StatsPeriodCompareRow] {
        let byID = Dictionary(uniqueKeysWithValues: periodCompareRows(currencyCode: currencyCode).map { ($0.id, $0) })
        let ids = hidesUnscopedCostComparison
            ? ["distance", "duration", "trips"]
            : ["distance", "duration", "expenses"]
        return ids.compactMap { byID[$0] }
    }

    private var heroMetricIDs: Set<String> {
        hidesUnscopedCostComparison
            ? ["distance", "duration", "trips"]
            : ["distance", "duration", "expenses"]
    }

    private var goalRing: some View {
        ZStack {
            Circle()
                .stroke(Color.blue.opacity(0.15), lineWidth: 7)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(goalPercentText)
                .font(.caption2.weight(.bold))
                .numericTextAnimation(value: goalPercentText)
        }
        .frame(width: 56, height: 56)
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
            GridItem(.flexible(), spacing: 5),
            GridItem(.flexible(), spacing: 5)
        ]
        let items = summaryMetricItems(currencyCode: currencyCode)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            if showsSummarySkeleton {
                ForEach(0..<items.count, id: \.self) { index in
                    StatsSummaryTileSkeleton(reduceMotion: reduceMotion)
                        .accessibilityIdentifier("stats.summary.skeleton.\(index)")
                }
            } else {
                ForEach(items) { item in
                    summaryMetricCard(
                        title: item.title,
                        value: item.value,
                        trend: item.trend,
                        previousText: item.previousText,
                        helpTitle: item.helpTitle,
                        helpBody: item.helpBody
                    )
                }
            }
        }
        .accessibilityElement(children: showsSummarySkeleton ? .ignore : .contain)
        .accessibilityIdentifier(showsSummarySkeleton ? "stats.summary.skeleton" : "stats.summary.grid")
        .modifier(StatsSummaryGridAccessibility(isLoading: showsSummarySkeleton))
        .animation(nil, value: showsSummarySkeleton)
    }

    private func summaryMetricItems(currencyCode: String) -> [StatsSummaryMetricItem] {
        let skip = heroMetricIDs
        let compareByID = Dictionary(
            uniqueKeysWithValues: periodCompareRows(currencyCode: currencyCode).map { ($0.id, $0) }
        )
        var items: [StatsSummaryMetricItem] = []
        if !skip.contains("trips") {
            items.append(
                StatsSummaryMetricItem(
                    id: "trips",
                    title: L10n.string("stats.trips"),
                    value: "\(snap.stats.tripCount)",
                    trend: snap.tripCountTrend,
                    previousText: compareByID["trips"]?.previousText
                )
            )
        }
        if !skip.contains("distance") {
            items.append(
                StatsSummaryMetricItem(
                    id: "distance",
                    title: L10n.string("stats.total_distance"),
                    value: snap.stats.totalDistanceText,
                    trend: snap.distanceTrend,
                    previousText: compareByID["distance"]?.previousText
                )
            )
        }
        if !skip.contains("duration") {
            items.append(
                StatsSummaryMetricItem(
                    id: "duration",
                    title: L10n.string("stats.total_duration"),
                    value: snap.stats.totalDurationText,
                    trend: snap.durationTrend,
                    previousText: compareByID["duration"]?.previousText
                )
            )
        }
        if !hidesUnscopedCostComparison, !skip.contains("expenses") {
            items.append(
                StatsSummaryMetricItem(
                    id: "expenses",
                    title: L10n.string("stats.total_expenses"),
                    value: costSnapshot.total > 0
                        ? FuelCostCalculator.formatCost(costSnapshot.total, currencyCode: currencyCode)
                        : "—",
                    trend: costSnapshot.expenseTrend,
                    previousText: compareByID["expenses"]?.previousText
                )
            )
        }
        items.append(contentsOf: [
            StatsSummaryMetricItem(
                id: "averageDuration",
                title: L10n.string("stats.average_duration"),
                value: snap.stats.averageDurationText
            ),
            StatsSummaryMetricItem(
                id: "averageSpeed",
                title: L10n.string("stats.average_speed"),
                value: snap.stats.averageSpeedText,
                trend: snap.averageSpeedTrend
            ),
            StatsSummaryMetricItem(
                id: "maxSpeed",
                title: L10n.string("stats.max_speed"),
                value: snap.stats.maxSpeedText,
                trend: snap.maxSpeedTrend
            ),
            StatsSummaryMetricItem(
                id: "cruiseSpeed",
                title: L10n.string("stats.cruise_speed"),
                value: snap.stats.cruiseSpeedText,
                trend: snap.cruiseSpeedTrend,
                helpTitle: L10n.cruiseSpeedHelpTitle,
                helpBody: L10n.cruiseSpeedHelpBody
            ),
            StatsSummaryMetricItem(
                id: "mostCommonSpeed",
                title: L10n.string("stats.most_common_speed"),
                value: snap.stats.mostCommonSpeedText,
                trend: snap.mostCommonSpeedTrend,
                helpTitle: L10n.mostCommonSpeedHelpTitle,
                helpBody: L10n.mostCommonSpeedHelpBody
            ),
            StatsSummaryMetricItem(
                id: "stopDuration",
                title: L10n.string("stats.stop_duration"),
                value: snap.stats.stopDurationText,
                trend: snap.stopDurationTrend
            ),
            StatsSummaryMetricItem(
                id: "estimatedFuel",
                title: L10n.string("stats.total_estimated_fuel"),
                value: FuelCostCalculator.formatCost(snap.stats.estimatedFuelCost, currencyCode: currencyCode),
                trend: snap.fuelCostTrend,
                previousText: compareByID["fuel"]?.previousText
            ),
            StatsSummaryMetricItem(
                id: "dynamicFuel",
                title: L10n.string("stats.total_dynamic_fuel"),
                value: snap.stats.dynamicFuelCost > 0
                    ? FuelCostCalculator.formatCost(snap.stats.dynamicFuelCost, currencyCode: currencyCode)
                    : "—",
                trend: snap.dynamicFuelCostTrend,
                helpTitle: L10n.dynamicFuelHelpTitle,
                helpBody: L10n.dynamicFuelHelpBody
            ),
            StatsSummaryMetricItem(
                id: "costPerKm",
                title: L10n.string("stats.cost_per_km"),
                value: snap.stats.costPerKm > 0
                    ? FuelCostCalculator.formatCost(snap.stats.costPerKm, currencyCode: currencyCode)
                    : "—"
            ),
            StatsSummaryMetricItem(
                id: "dynamicCostPerKm",
                title: L10n.string("stats.dynamic_cost_per_km"),
                value: snap.stats.dynamicCostPerKm > 0
                    ? FuelCostCalculator.formatCost(snap.stats.dynamicCostPerKm, currencyCode: currencyCode)
                    : "—"
            ),
            StatsSummaryMetricItem(
                id: "averageCostPerTrip",
                title: L10n.string("stats.average_cost_per_trip"),
                value: snap.stats.averageCostPerTrip > 0
                    ? FuelCostCalculator.formatCost(snap.stats.averageCostPerTrip, currencyCode: currencyCode)
                    : "—"
            ),
            StatsSummaryMetricItem(
                id: "dynamicCostPerTrip",
                title: L10n.string("stats.dynamic_cost_per_trip"),
                value: snap.stats.dynamicCostPerTrip > 0
                    ? FuelCostCalculator.formatCost(snap.stats.dynamicCostPerTrip, currencyCode: currencyCode)
                    : "—"
            ),
            StatsSummaryMetricItem(
                id: "nightDriving",
                title: L10n.string("stats.night_driving"),
                value: snap.stats.nightDrivingText
            )
        ])
        return items
    }

    private func summaryMetricCard(
        title: String,
        value: String,
        trend: StatsTrend? = nil,
        previousText: String? = nil,
        helpTitle: String? = nil,
        helpBody: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .center, spacing: 4) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let helpTitle, let helpBody {
                    HelpPopoverButton(
                        accessibilityLabel: helpTitle,
                        message: helpBody,
                        side: 16
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(height: StatsCardTokens.nestedTileTitleRowHeight)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 0)
                StatsTrendBadge(trend: trend, metricName: title)
            }

            Text(previousText.map { "\(comparePreviousLabel) \($0)" } ?? " ")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: StatsCardTokens.nestedTilePreviousLineHeight, alignment: .topLeading)
                .opacity(previousText == nil ? 0 : 1)
                .accessibilityHidden(previousText == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .statsNestedTile()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            summaryAccessibilityLabel(
                title: title,
                value: value,
                trend: trend,
                previousText: previousText
            )
        )
    }

    private func summaryAccessibilityLabel(
        title: String,
        value: String,
        trend: StatsTrend?,
        previousText: String? = nil
    ) -> String {
        var parts = [title, value]
        if let previousText {
            parts.append("\(comparePreviousLabel) \(previousText)")
        }
        if let trend {
            parts.append(trend.accessibilityLabel(metricName: title))
        }
        return parts.joined(separator: ", ")
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
            if let date = value.as(Date.self) {
                AxisValueLabel(centered: true) {
                    Text(dailyAxisDayLabel(date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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

    private var hidesUnscopedCostComparison: Bool {
        StatsViewModel.hidesUnscopedCostComparison(
            categoryID: selectedCategoryID,
            placeName: selectedPlaceName,
            journalID: selectedJournalID
        )
    }

    private var vehicleCompareRows: [VehicleCompareRow] {
        StatsVehicleCompareBuilder.rows(
            seeds: costSnapshot.compareSeeds,
            distances: snap.vehicleDistance
        )
    }

    private var showsVehicleCompareList: Bool {
        StatsViewModel.showsVehicleCompareList(
            hidesUnscopedCosts: hidesUnscopedCostComparison,
            selectedVehicleID: selectedVehicleID,
            rowCount: vehicleCompareRows.count
        )
    }

    private var compareCurrentLabel: String {
        switch selectedPeriod {
        case .week: L10n.string("stats.compare.this_week")
        case .month: L10n.string("stats.compare.this_month")
        case .custom: L10n.string("stats.compare.this_range")
        }
    }

    private var comparePreviousLabel: String {
        switch selectedPeriod {
        case .week: L10n.string("stats.compare.previous_week")
        case .month:
            if StatsViewModel.usesMonthToDatePrevious(for: .month, selectedMonth: selectedMonth) {
                L10n.string("stats.compare.same_days_last_month")
            } else {
                L10n.string("stats.compare.last_month")
            }
        case .custom: L10n.string("stats.compare.previous_range")
        }
    }

    private var awardsYears: [Int] {
        StatsViewModel.selectableYears(earliestTripStart: earliestTripStart)
    }

    private var yearAwardsMedals: [StatsYearAward] {
        guard let yearAwards else { return [] }
        return StatsYearAwardsPresenter.medals(
            from: yearAwards,
            goalMetersForMonth: { settings.goalMeters(forMonthContaining: $0) },
            currencyCode: settings.fuelCurrency.rawValue
        )
    }

    private func periodCompareRows(currencyCode: String) -> [StatsPeriodCompareRow] {
        let stats = snap.stats
        let previous = snap.previousStats
        let dash = "—"
        let includeExpenses = !hidesUnscopedCostComparison
        let expenseCurrent = costSnapshot.total > 0
            ? FuelCostCalculator.formatCost(costSnapshot.total, currencyCode: currencyCode)
            : dash
        let expensePrevious = costSnapshot.previousTotal > 0
            ? FuelCostCalculator.formatCost(costSnapshot.previousTotal, currencyCode: currencyCode)
            : dash
        let byID: [String: StatsPeriodCompareRow] = [
            "trips": StatsPeriodCompareRow(
                id: "trips",
                title: L10n.string("stats.trips"),
                currentText: "\(stats.tripCount)",
                previousText: "\(previous.tripCount)",
                trend: snap.tripCountTrend
            ),
            "distance": StatsPeriodCompareRow(
                id: "distance",
                title: L10n.string("stats.total_distance"),
                currentText: stats.totalDistanceText,
                previousText: previous.totalDistanceText,
                trend: snap.distanceTrend
            ),
            "duration": StatsPeriodCompareRow(
                id: "duration",
                title: L10n.string("stats.total_duration"),
                currentText: stats.totalDurationText,
                previousText: previous.totalDurationText,
                trend: snap.durationTrend
            ),
            "expenses": StatsPeriodCompareRow(
                id: "expenses",
                title: L10n.string("stats.total_expenses"),
                currentText: expenseCurrent,
                previousText: expensePrevious,
                trend: costSnapshot.expenseTrend
            ),
            "fuel": StatsPeriodCompareRow(
                id: "fuel",
                title: L10n.string("stats.total_estimated_fuel"),
                currentText: FuelCostCalculator.formatCost(stats.estimatedFuelCost, currencyCode: currencyCode),
                previousText: FuelCostCalculator.formatCost(previous.estimatedFuelCost, currencyCode: currencyCode),
                trend: snap.fuelCostTrend
            )
        ]
        return StatsViewModel.periodCompareMetricIDs(includeExpenses: includeExpenses).compactMap { byID[$0] }
    }

    private func clampSelectedAwardsYear() {
        let years = awardsYears
        if !years.contains(selectedAwardsYear) {
            selectedAwardsYear = years.first ?? Calendar.current.component(.year, from: Date())
        }
    }

    private func scheduleYearAwardsRefresh(delayMilliseconds: Int) {
        guard hasCompletedInitialSnapshot else { return }
        yearAwardsRefreshTask?.cancel()
        let loader = yearAwardsLoader ?? StatsYearAwardsLoader(modelContainer: modelContext.container)
        if yearAwardsLoader == nil {
            yearAwardsLoader = loader
        }
        clampSelectedAwardsYear()
        let request = StatsYearAwardsRequest(storeVersion: storeVersion, year: selectedAwardsYear)
        yearAwardsRefreshTask = Task {
            if delayMilliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }
            let built = await loader.snapshot(for: request)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                yearAwards = built
            }
        }
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

    private func dailyDistanceChartBody(_ dailyChartData: [DailyDistance]) -> some View {
        let days = dailyChartData.map(\.day)
        return Chart(dailyChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.distance_km"), item.distanceKilometers)
            )
            .foregroundStyle(StatsChartTheme.distanceBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyChartData.map(\.distanceKilometers).max() ?? 0)
        .chartStatsQuietYAxisStyle()
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
            .foregroundStyle(StatsChartTheme.durationBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyDurationChartData.map(\.durationHours).max() ?? 0)
        .chartStatsQuietYAxisStyle()
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
            .foregroundStyle(StatsChartTheme.averageSpeedBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyAverageSpeedChartData.map(\.speedKmh).max() ?? 0)
        .chartStatsQuietYAxisStyle()
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
            .foregroundStyle(StatsChartTheme.maxSpeedBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyMaxSpeedChartData.map(\.speedKmh).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.speed_kmh"))
        .frame(height: 200)
    }

    private func dailyCruiseSpeedChartBody(_ dailyCruiseSpeedChartData: [DailyCruiseSpeed]) -> some View {
        let days = dailyCruiseSpeedChartData.map(\.day)
        return Chart(dailyCruiseSpeedChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.speed_kmh"), item.speedKmh)
            )
            .foregroundStyle(StatsChartTheme.cruiseSpeedBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyCruiseSpeedChartData.map(\.speedKmh).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.speed_kmh"))
        .frame(height: 200)
    }

    private func dailyMostCommonSpeedChartBody(_ dailyMostCommonSpeedChartData: [DailyMostCommonSpeed]) -> some View {
        let days = dailyMostCommonSpeedChartData.map(\.day)
        return Chart(dailyMostCommonSpeedChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.speed_kmh"), item.speedKmh)
            )
            .foregroundStyle(StatsChartTheme.mostCommonSpeedBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyMostCommonSpeedChartData.map(\.speedKmh).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.speed_kmh"))
        .frame(height: 200)
    }

    private func dailyStopDurationChartBody(_ dailyStopDurationChartData: [DailyStopDuration]) -> some View {
        let days = dailyStopDurationChartData.map(\.day)
        return Chart(dailyStopDurationChartData) { item in
            BarMark(
                x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                y: .value(L10n.string("stats.chart.duration_hours"), item.durationHours)
            )
            .foregroundStyle(StatsChartTheme.stopDurationBarFill)
            .cornerRadius(StatsChartTheme.barCornerRadius)
        }
        .chartBarValueHeadroom(maxValue: dailyStopDurationChartData.map(\.durationHours).max() ?? 0)
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.duration_hours"))
        .frame(height: 200)
    }

    private func dailyFuelCostChartBody(_ dailyFuelCostChartData: [DailyFuelCost]) -> some View {
        let days = dailyFuelCostChartData.map(\.day)
        let avgLabel = L10n.string("stats.chart.fuel_avg")
        let estLabel = L10n.string("stats.chart.fuel_estimated")
        let avgColor = Color(red: 0.28, green: 0.78, blue: 0.86)
        let estColor = Color(red: 0.98, green: 0.58, blue: 0.24)
        let maxValue = dailyFuelCostChartData.map { max($0.cost, $0.dynamicCost) }.max() ?? 0

        return Chart {
            ForEach(dailyFuelCostChartData) { item in
                BarMark(
                    x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                    y: .value(L10n.string("stats.chart.fuel_cost"), item.cost)
                )
                .foregroundStyle(by: .value("series", avgLabel))
                .position(by: .value("series", avgLabel))
                .cornerRadius(StatsChartTheme.barCornerRadius)

                BarMark(
                    x: .value(L10n.string("stats.chart.day"), item.day, unit: .day),
                    y: .value(L10n.string("stats.chart.fuel_cost"), item.dynamicCost)
                )
                .foregroundStyle(by: .value("series", estLabel))
                .position(by: .value("series", estLabel))
                .cornerRadius(StatsChartTheme.barCornerRadius)
            }
        }
        .chartForegroundStyleScale([
            avgLabel: avgColor,
            estLabel: estColor
        ])
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYScale(domain: [0, max(maxValue * 1.12, 1)])
        .chartStatsQuietYAxisStyle()
        .chartXAxis { dailyChartXAxis(days: days) }
        .chartYAxisLabel(L10n.string("stats.chart.fuel_cost"))
        .frame(height: 200)
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
    let journalCount: Int
    let period: StatsPeriod
    let customStart: Date
    let customEnd: Date
    let selectedMonth: Date
    let selectedCategoryID: String?
    let selectedVehicleID: UUID?
    let selectedPlaceID: UUID?
    let selectedPlaceName: String?
    let selectedJournalID: UUID?
}

private struct StatsSummaryMetricItem: Identifiable {
    let id: String
    let title: String
    let value: String
    var trend: StatsTrend? = nil
    var previousText: String? = nil
    var helpTitle: String? = nil
    var helpBody: String? = nil
}

private struct StatsSummaryGridAccessibility: ViewModifier {
    var isLoading: Bool

    func body(content: Content) -> some View {
        if isLoading {
            content.accessibilityLabel(L10n.statsSummaryLoading)
        } else {
            content
        }
    }
}

private enum StatsFilterDefaults {
    static func selectedMonth(now: Date = Date()) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now)) ?? now
    }

    static func customStart(now: Date = Date()) -> Date {
        Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
    }
}

/// Title + truncated value + chevron; Menu picker keeps long names on one line.
private struct StatsFilterMenuField<MenuContent: View>: View {
    let title: String
    let value: String
    let isActive: Bool
    let identifier: String
    var avatarSystemImage: String?
    var avatarPhotoFileName: String?
    var avatarIsElectric: Bool
    let menuContent: MenuContent

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        value: String,
        isActive: Bool,
        identifier: String,
        avatarSystemImage: String? = nil,
        avatarPhotoFileName: String? = nil,
        avatarIsElectric: Bool = false,
        @ViewBuilder menuContent: () -> MenuContent
    ) {
        self.title = title
        self.value = value
        self.isActive = isActive
        self.identifier = identifier
        self.avatarSystemImage = avatarSystemImage
        self.avatarPhotoFileName = avatarPhotoFileName
        self.avatarIsElectric = avatarIsElectric
        self.menuContent = menuContent()
    }

    var body: some View {
        Menu {
            menuContent
        } label: {
            fieldLabel
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .tint(TrailhoundBrandColors.brandBottom)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private var fieldLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                if let avatarSystemImage {
                    VehicleAvatarView(
                        systemImage: avatarSystemImage,
                        photoFileName: avatarPhotoFileName,
                        size: 18,
                        cornerRadius: 5,
                        isElectricAccent: avatarIsElectric,
                        showsSymbolPlate: false,
                        symbolFitsFrame: true
                    )
                    .accessibilityHidden(true)
                }

                Text(value)
                    .font(.subheadline.weight(isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? TrailhoundBrandColors.brandBottom : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 4)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .glassField(cornerRadius: 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
    }

    private var borderColor: Color {
        if isActive {
            return TrailhoundBrandColors.brandBottom.opacity(0.55)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.35)
    }
}

private extension View {
    func statsHiddenDonutLegend(height: CGFloat) -> some View {
        chartLegend(.hidden)
            .frame(height: height)
    }
}

#Preview {
    NavigationStack { StatsView() }
        .modelContainer(PreviewData.shared.container)
}
