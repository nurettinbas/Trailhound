import SwiftData
import SwiftUI

struct YearView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var tabSelection = TabSelection.shared

    @State private var storeVersion = 0
    @State private var earliestTripStart: Date?
    @State private var forecastLoader: MonthCostForecastLoader?
    @State private var forecast: MonthCostForecast = .empty
    @State private var recapLoader: YearRecapSnapshotLoader?
    @State private var recapSnapshot: YearRecapSnapshot?
    @State private var achievements: [AchievementDisplay] = []
    @State private var routeAggregates: [FrequentRouteAggregate] = []
    @State private var showForecastDetail = false
    @State private var forecastExpanded = false
    @State private var forecastCardFrame: CGRect = .zero
    @State private var frozenForecastCardFrame: CGRect = .zero
    @State private var showAchievements = false
    @State private var achievementsExpanded = false
    @State private var badgesCardFrame: CGRect = .zero
    @State private var frozenBadgesCardFrame: CGRect = .zero
    @State private var showRoutesMap = false
    @State private var routesExpanded = false
    @State private var routesCardFrame: CGRect = .zero
    @State private var frozenRoutesCardFrame: CGRect = .zero
    @State private var pendingRecapPlay = false
    @State private var recapStorySession: RecapStorySession?
    @State private var unlockQueue: [AchievementDisplay] = []
    @State private var yearAwardsLoader: StatsYearAwardsLoader?
    @State private var yearAwards: StatsYearAwardsSnapshot?
    @State private var selectedAwardsYear = Calendar.current.component(.year, from: Date())
    @State private var yearAwardsRefreshTask: Task<Void, Never>?

    var body: some View {
        yearList(currencyCode: settings.fuelCurrency.rawValue)
            .glassListChrome()
            .navigationTitle(L10n.tabYear)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: handleYearAppear)
            .onStoreSave(perform: handleYearStoreSave)
            .onDisappear {
                yearAwardsRefreshTask?.cancel()
            }
            .onChange(of: selectedAwardsYear) { _, _ in
                scheduleYearAwardsRefresh(delayMilliseconds: 0)
            }
            .onChange(of: earliestTripStart) { _, _ in
                clampSelectedAwardsYear()
            }
            .onChange(of: tabSelection.pendingStatsAnchor) { _, _ in
                consumeYearDeepLink()
            }
            .onPreferenceChange(AchievementCardGlobalFrameKey.self) { badgesCardFrame = $0 }
            .onPreferenceChange(FrequentRoutesCardGlobalFrameKey.self) { routesCardFrame = $0 }
            .onPreferenceChange(StatsForecastCardGlobalFrameKey.self) { forecastCardFrame = $0 }
            .fullScreenCover(isPresented: $showAchievements) {
                AchievementGalleryExpandOverlay(
                    achievements: achievements,
                    sourceGlobal: frozenBadgesCardFrame,
                    isExpanded: $achievementsExpanded,
                    onClose: closeAchievements
                )
                .presentationBackground(.clear)
                .interactiveDismissDisabled()
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showRoutesMap) {
                FrequentRoutesExpandOverlay(
                    aggregates: routeAggregates,
                    sourceGlobal: frozenRoutesCardFrame,
                    isExpanded: $routesExpanded,
                    onClose: closeRoutesMap
                )
                .presentationBackground(.clear)
                .interactiveDismissDisabled()
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showForecastDetail) {
                StatsForecastExpandOverlay(
                    forecast: forecast,
                    currencyCode: settings.fuelCurrency.rawValue,
                    sourceGlobal: frozenForecastCardFrame,
                    isExpanded: $forecastExpanded,
                    onClose: closeForecastDetail
                )
                .presentationBackground(.clear)
                .interactiveDismissDisabled()
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $recapStorySession) { session in
                YearRecapStoryView(snapshot: session.snapshot) {
                    markRecapSeen()
                    recapStorySession = nil
                }
                .interactiveDismissDisabled()
            }
            .overlay {
                achievementUnlockOverlay
            }
    }

    @ViewBuilder
    private func yearList(currencyCode: String) -> some View {
        List {
            Section {
                StatsYearAwardsCard(
                    snapshot: yearAwards,
                    medals: yearAwardsMedals,
                    years: awardsYears,
                    selectedYear: $selectedAwardsYear,
                    reduceMotion: reduceMotion,
                    onAppear: {
                        scheduleYearAwardsRefresh(delayMilliseconds: 0)
                    }
                )
                .statsFullCard()
            }

            Section(L10n.string("premium.section.title")) {
                StatsAchievementsStrip(
                    achievements: achievements,
                    isExpanded: showAchievements,
                    onOpen: openAchievements
                )
                .statsFullCard()
                .opacity(showAchievements ? 0 : 1)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: AchievementCardGlobalFrameKey.self,
                            value: proxy.frame(in: .global)
                        )
                    }
                }

                FrequentRoutesPreviewCard(
                    aggregates: routeAggregates,
                    isExpanded: showRoutesMap,
                    onOpen: openRoutesMap
                )
                .statsFullCard()
                .opacity(showRoutesMap ? 0 : 1)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: FrequentRoutesCardGlobalFrameKey.self,
                            value: proxy.frame(in: .global)
                        )
                    }
                }

                StatsForecastCard(
                    forecast: forecast,
                    currencyCode: currencyCode,
                    isExpanded: showForecastDetail,
                    onOpen: openForecastDetail
                )
                .statsFullCard(contentInset: 0)
                .opacity(showForecastDetail ? 0 : 1)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: StatsForecastCardGlobalFrameKey.self,
                            value: proxy.frame(in: .global)
                        )
                    }
                }

                YearRecapHubCard(
                    snapshot: recapSnapshot ?? .empty(year: RecapYearPolicy.displayYear()),
                    onPlay: { openRecapStory() }
                )
                .statsFullCard(contentInset: 0)
            }
        }
    }

    @ViewBuilder
    private var achievementUnlockOverlay: some View {
        ZStack {
            if let item = unlockQueue.first {
                Color.black.opacity(0.28).ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        advanceUnlockQueue(from: item)
                    }
                AchievementUnlockOverlay(item: item) {
                    advanceUnlockQueue(from: item)
                }
                .id(item.id)
                .transition(TrailhoundMotion.badgeUnlockCardTransition(reduceMotion: reduceMotion))
            }
        }
        .animation(TrailhoundMotion.badgeUnlock(reduceMotion: reduceMotion), value: unlockQueue.first?.id)
        .allowsHitTesting(unlockQueue.first != nil)
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

    private func handleYearAppear() {
        if forecastLoader == nil {
            forecastLoader = MonthCostForecastLoader(modelContainer: modelContext.container)
        }
        if recapLoader == nil {
            recapLoader = YearRecapSnapshotLoader(modelContainer: modelContext.container)
        }
        refreshEarliestTripStart()
        schedulePremiumRefresh()
        scheduleYearAwardsRefresh(delayMilliseconds: 0)
        consumeYearDeepLink()
    }

    private func handleYearStoreSave() {
        refreshEarliestTripStart()
        storeVersion &+= 1
        schedulePremiumRefresh()
        scheduleYearAwardsRefresh(delayMilliseconds: 0)
    }

    private func schedulePremiumRefresh() {
        let forecastActor = forecastLoader ?? MonthCostForecastLoader(modelContainer: modelContext.container)
        if forecastLoader == nil { forecastLoader = forecastActor }
        let recapActor = recapLoader ?? YearRecapSnapshotLoader(modelContainer: modelContext.container)
        if recapLoader == nil { recapLoader = recapActor }
        let year = RecapYearPolicy.displayYear()
        let request = MonthCostForecastRequest(
            storeVersion: storeVersion,
            selectedVehicleID: nil,
            now: Date()
        )
        Task {
            let builtForecast = await forecastActor.forecast(for: request)
            let builtRecap = await recapActor.snapshot(year: year, storeVersion: storeVersion)
            await MainActor.run {
                forecast = builtForecast
                recapSnapshot = builtRecap
                _ = AchievementEvaluator.displays(in: modelContext)
                if !UITestSupport.isEnabled {
                    _ = AchievementEvaluator.replayUnlockCelebrationsIfNeeded(in: modelContext)
                }
                achievements = AchievementEvaluator.displays(in: modelContext)
                routeAggregates = FrequentRouteAggregateService.topAggregates(in: modelContext)
                let pending = achievements.filter(\.needsCelebration)
                unlockQueue = AchievementUnlockQueue.merging(queued: unlockQueue, pending: pending)
                PremiumWidgetBridge.sync(in: modelContext, forecast: builtForecast)
                if pendingRecapPlay {
                    pendingRecapPlay = false
                    if RecapYearPolicy.shouldPresent(builtRecap) {
                        recapStorySession = RecapStorySession(snapshot: builtRecap)
                    }
                } else {
                    maybeAutoplayRecap()
                }
            }
        }
    }

    private func scheduleYearAwardsRefresh(delayMilliseconds: Int) {
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

    private func refreshEarliestTripStart() {
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        earliestTripStart = (try? modelContext.fetch(descriptor))?.first?.startedAt
    }

    private func clampSelectedAwardsYear() {
        let years = awardsYears
        if !years.contains(selectedAwardsYear) {
            selectedAwardsYear = years.first ?? Calendar.current.component(.year, from: Date())
        }
    }

    private func openAchievements() {
        guard !showAchievements else { return }
        TrailhoundHaptics.selection()
        frozenBadgesCardFrame = badgesCardFrame
        let morph = !reduceMotion && AchievementGalleryExpandLayout.hasUsableSource(frozenBadgesCardFrame)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showAchievements = true
            achievementsExpanded = !morph
        }
        guard morph else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(TrailhoundMotion.badgeCardExpand(reduceMotion: false)) {
                achievementsExpanded = true
            }
        }
    }

    private func closeAchievements() {
        TrailhoundHaptics.selection()
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                achievementsExpanded = false
                showAchievements = false
            }
            return
        }
        withAnimation(TrailhoundMotion.badgeCardExpand(reduceMotion: false)) {
            achievementsExpanded = false
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showAchievements = false
            }
        }
    }

    private func openRoutesMap() {
        guard !showRoutesMap else { return }
        TrailhoundHaptics.selection()
        frozenRoutesCardFrame = routesCardFrame
        let morph = !reduceMotion && AchievementGalleryExpandLayout.hasUsableSource(frozenRoutesCardFrame)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showRoutesMap = true
            routesExpanded = !morph
        }
        guard morph else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(TrailhoundMotion.badgeCardExpand(reduceMotion: false)) {
                routesExpanded = true
            }
        }
    }

    private func closeRoutesMap() {
        TrailhoundHaptics.selection()
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                routesExpanded = false
                showRoutesMap = false
            }
            return
        }
        withAnimation(TrailhoundMotion.badgeCardExpand(reduceMotion: false)) {
            routesExpanded = false
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showRoutesMap = false
            }
        }
    }

    private func openForecastDetail() {
        guard !showForecastDetail else { return }
        TrailhoundHaptics.selection()
        frozenForecastCardFrame = forecastCardFrame
        let morph = !reduceMotion && AchievementGalleryExpandLayout.hasUsableSource(frozenForecastCardFrame)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showForecastDetail = true
            forecastExpanded = !morph
        }
        guard morph else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(TrailhoundMotion.badgeCardExpand(reduceMotion: false)) {
                forecastExpanded = true
            }
        }
    }

    private func closeForecastDetail() {
        TrailhoundHaptics.selection()
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                forecastExpanded = false
                showForecastDetail = false
            }
            return
        }
        withAnimation(TrailhoundMotion.badgeCardExpand(reduceMotion: false)) {
            forecastExpanded = false
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showForecastDetail = false
            }
        }
    }

    private func consumeYearDeepLink() {
        guard let pending = tabSelection.pendingStatsAnchor else { return }
        switch pending {
        case .goal:
            return
        case .forecast, .recap, .routes, .achievements:
            break
        }
        guard let anchor = tabSelection.consumePendingStatsAnchor() else { return }
        switch anchor {
        case .goal:
            break
        case .forecast:
            openForecastDetail()
        case .recap:
            playRecapWhenReady()
        case .routes:
            openRoutesMap()
        case .achievements:
            openAchievements()
        }
    }

    private func playRecapWhenReady() {
        if RecapYearPolicy.shouldPresent(recapSnapshot) {
            openRecapStory()
            return
        }
        pendingRecapPlay = true
        schedulePremiumRefresh()
    }

    private func openRecapStory() {
        guard let recapSnapshot, recapSnapshot.hasData else { return }
        recapStorySession = RecapStorySession(snapshot: recapSnapshot)
    }

    private func recapSeenKey(for year: Int) -> String {
        RecapYearPolicy.seenKey(for: year)
    }

    private func markRecapSeen() {
        let year = RecapYearPolicy.displayYear()
        RecapNotificationScheduler.noteRecapConsumed(year: year)
    }

    private func maybeAutoplayRecap() {
        guard recapStorySession == nil else { return }
        guard !UITestSupport.isEnabled, !UITestSupport.isUnitTesting else { return }
        let year = RecapYearPolicy.displayYear()
        let month = Calendar.current.component(.month, from: Date())
        guard month == 12 || month == 1 else { return }
        guard RecapYearPolicy.shouldPresent(recapSnapshot) else { return }
        guard !UserDefaults.standard.bool(forKey: recapSeenKey(for: year)) else { return }
        openRecapStory()
        markRecapSeen()
    }

    private func advanceUnlockQueue(from item: AchievementDisplay) {
        guard unlockQueue.contains(where: { $0.id == item.id }) else { return }
        AchievementEvaluator.markSeen([item.id], in: modelContext)
        withAnimation(TrailhoundMotion.badgeUnlock(reduceMotion: reduceMotion)) {
            unlockQueue.removeAll { $0.id == item.id }
        }
        try? modelContext.save()
        achievements = AchievementEvaluator.displays(in: modelContext)
    }
}
