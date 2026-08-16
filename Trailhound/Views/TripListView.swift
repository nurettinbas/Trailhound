import SwiftData
import SwiftUI

struct TripListView: View {
    // Deliberately no `@Query` for trips: the list pages through the store instead of holding
    // every trip in memory. `ModelContext.didSave` stands in for the change tracking.
    @Query private var places: [SavedPlace]
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Query private var vehicles: [VehicleProfile]
    @Query private var schedules: [VehicleSchedule]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TripRecordingService.self) private var recordingService
    @Bindable private var settings = AppSettings.shared

    @Bindable private var notificationStore = AppNotificationStore.shared
    @Bindable private var careSummary = VehicleCareSummaryStore.shared

    @State private var selectedLabel: String?
    @State private var selectedCategoryID: String?
    @State private var selectedDateSection: TripDateSection?
    @State private var selectedVehicleFilter: TripListPage.VehicleFilter?
    @State private var selectedPlaceID: UUID?
    @State private var mergeSelection = Set<UUID>()
    @State private var isMergeMode = false
    @State private var isMerging = false
    @State private var aggregatesRefreshTask: Task<Void, Never>?
    @Bindable private var tabSelection = TabSelection.shared

    @State private var orphanTrips: [TripRecoveryService.OrphanTrip] = []
    @State private var showMergeConfirm = false
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @FocusState private var isSearchFocused: Bool
    @Namespace private var tripMorphNamespace
    @State private var morphingTripID: UUID?
    @State private var endCredits: RecordingEndCreditsSnapshot?
    /// How far the floating blue bar has slid down toward the trip list.
    @State private var creditsSlideY: CGFloat = 0
    @State private var isCreditsSliding = false
    @State private var listLandingMinY: CGFloat = 0
    /// Pinned at Stop so overlay keeps the live recording card's exact frame.
    @State private var pinnedCreditsCardAnchor = RecordingCardAnchor()
    /// Armed before recording state flips so entrance anim can't lose the race on device.
    @State private var coldOpenArmed = false
    @State private var coldOpenTripID: UUID?
    @State private var showNotificationsList = false
    @State private var scrollToTopToken = 0
    @State private var scrollToTopRequest: TripListScrollToTopRequest?
    @State private var isRecordingCardInViewport = true
    @State private var showLiveFollowMap = false
    @State private var liveFollowCardAnchor = RecordingCardAnchor()
    @State private var liveFollowVehiclePhoto: UIImage?

    /// The pages fetched so far, newest first.
    @State private var loadedTrips: [Trip] = []
    /// Grouped alongside the fetch so the sort does not rerun on every body pass.
    @State private var tripGroups: [(section: TripDateSection, trips: [Trip])] = []
    @State private var pageLimit = TripListPage.pageSize
    @State private var hasMorePages = false
    @State private var hasAnyTrips = false
    @State private var weekSummaryText = ""

    private var hasActiveFilters: Bool {
        pageFilters.isActive
    }

    private var selectedPlaceName: String? {
        guard let selectedPlaceID else { return nil }
        return places.first(where: { $0.id == selectedPlaceID })?.name
    }

    private var pageFilters: TripListPage.Filters {
        TripListPage.Filters(
            searchText: debouncedSearchText,
            categoryID: selectedCategoryID,
            dateSection: selectedDateSection,
            label: selectedLabel,
            vehicleFilter: selectedVehicleFilter,
            placeName: selectedPlaceName
        )
    }

    private var completedTrips: [Trip] {
        loadedTrips
    }

    /// Selection may include unfinished/orphan rows; only completed legs can merge.
    private var completedMergeSelectionCount: Int {
        loadedTrips.filter { mergeSelection.contains($0.id) && $0.endedAt != nil }.count
    }

    private func reloadTrips() {
        let filters = pageFilters
        let fetched = (try? modelContext.fetch(
            TripListPage.descriptor(filters: filters, limit: pageLimit)
        )) ?? []

        hasMorePages = fetched.count > pageLimit
        let visible = Array(fetched.prefix(pageLimit)).filter { matchesInMemoryFilters($0, filters) }
        loadedTrips = visible
        tripGroups = TripDateGrouping.groupedSections(from: visible)
    }

    /// The parts of a filter the store cannot answer exactly: date-section boundaries move with
    /// the wall clock, labels are free text, and trips still awaiting a search index need the
    /// legacy field scan. Place names are also re-checked so a renamed favorite stays consistent
    /// with the chip's current `SavedPlace.name`. When a place chip is active the SQLite
    /// predicate omits `searchIndex` (type-checker limit), so search is always verified here.
    private func matchesInMemoryFilters(_ trip: Trip, _ filters: TripListPage.Filters) -> Bool {
        if let label = filters.label, trip.label != label { return false }
        if let section = filters.dateSection,
           !TripDateGrouping.matches(section, date: trip.startedAt) {
            return false
        }
        if !TripPlaceFilter.matches(
            startPlaceName: trip.startPlaceName,
            endPlaceName: trip.endPlaceName,
            placeName: filters.placeName
        ) {
            return false
        }
        let needsSearchScan = trip.searchIndex == nil || filters.placeName != nil
        if needsSearchScan {
            return TripListViewModel.matchesSearch(
                trip,
                searchText: filters.searchText,
                places: places,
                privacyRadius: settings.privacyRadiusMeters
            )
        }
        return true
    }

    private func loadNextPage() {
        guard hasMorePages else { return }
        pageLimit += TripListPage.pageSize
        reloadTrips()
    }

    private func resetPagingAndReload() {
        pageLimit = TripListPage.pageSize
        reloadTrips()
    }

    private func refreshListAggregates() {
        hasAnyTrips = (try? modelContext.fetchCount(TripListPage.completedCountDescriptor())).map { $0 > 0 }
            ?? false

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekTrips = (try? modelContext.fetch(
            TripListPage.completedInDescriptor(from: weekAgo)
        )) ?? []
        let stats = StatsViewModel.stats(for: weekTrips, includeNightRatio: false)
        weekSummaryText = L10n.weekSummary(
            distance: stats.totalDistanceText,
            duration: stats.totalDurationText
        )
    }

    private func newestCompletedTrip() -> Trip? {
        (try? modelContext.fetch(TripListPage.newestCompletedDescriptor()))?.first
    }

    private var showsVehicleSetupPrompt: Bool {
        !settings.hasCompletedCarSetup
    }

    private var visibleOrphan: TripRecoveryService.OrphanTrip? {
        orphanTrips.first { orphan in
            !orphan.isStale && orphan.id != recordingService.activeTripID
        }
    }

    private var showsActiveRecordingNavAffordance: Bool {
        guard recordingService.state.isActiveSession,
              endCredits == nil,
              recordingService.activeTripID != nil
        else { return false }

        return !isRecordingCardInViewport
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            tripList(scrollProxy: scrollProxy)
        }
    }

    private func tripList(scrollProxy: ScrollViewProxy) -> some View {
        // Computed once per body pass. `completedTrips` used to be re-evaluated inside every
        // row, which made rendering the list quadratic in trip count.
        let visibleTrips = completedTrips
        let groups = tripGroups
        let firstTripID = visibleTrips.first?.id
        let hasAnyTrips = self.hasAnyTrips
        let weekSummary = hasAnyTrips ? weekSummaryText : ""

        return List {
            Section {
                LocationPermissionBanner()
                    .id(TripListScrollTarget.top)
                    .background {
                        TripListScrollToTopInstaller(request: scrollToTopRequest)
                    }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionSpacing(6)

            if showsVehicleSetupPrompt {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tripListSetupVehicleTitle)
                            .font(.headline)
                        Text(L10n.tripListSetupVehicleMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(L10n.string("onboarding.shortcuts.link")) {
                            tabSelection.openPairing()
                        }
                        .buttonStyle(.borderedProminent)

                        Button(L10n.vehiclePairingSkip) {
                            settings.skipCarSetup()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .glassListRow()
                .listSectionSpacing(6)
            }

            if let careItem = careSummary.topBannerItem {
                Section {
                    VehicleCareBannerView(
                        item: careItem,
                        onTap: {
                            tabSelection.openVehicleCare(vehicleID: careItem.vehicleID)
                        },
                        onDismiss: {
                            careSummary.dismissBanner(scheduleID: careItem.scheduleID)
                        }
                    )
                }
                .vehicleCareBannerRow(state: careItem.state)
                .listSectionSpacing(6)
            }

            if let orphan = visibleOrphan {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.orphanBannerTitle)
                            .font(.headline)
                        Text(L10n.orphanBannerMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button(L10n.orphanResume) {
                                if TripRecoveryService.resumeOrphan(orphan.trip, recordingService: recordingService) {
                                    refreshOrphans()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Button(L10n.orphanSave) {
                                if TripRecoveryService.finalizeOrphan(orphan.trip, in: modelContext, saveTrip: true) {
                                    ToastPresenter.shared.show(.orphanSaved)
                                    refreshOrphans()
                                }
                            }
                            .buttonStyle(.bordered)
                            Button(L10n.delete, role: .destructive) {
                                if TripRecoveryService.deleteOrphan(orphan.trip, in: modelContext) {
                                    ToastPresenter.shared.show(.deleted, playHaptic: false)
                                    refreshOrphans()
                                }
                            }
                            .destructiveTint()
                        }
                    }
                }
                .glassListRow()
                .listSectionSpacing(6)
            }

            if recordingService.state.isActiveSession,
               endCredits == nil,
               let activeTripID = recordingService.activeTripID {
                Section {
                    ActiveTripView(
                        morphNamespace: tripMorphNamespace,
                        morphID: activeTripID,
                        playEntranceReveal: coldOpenArmed && coldOpenTripID == activeTripID,
                        onEntranceFinished: finishColdOpen,
                        onStop: { anchor in beginEndCredits(cardAnchor: anchor) },
                        onOpenLiveFollow: { anchor in
                            liveFollowCardAnchor = anchor
                            Task { @MainActor in
                                await prepareLiveFollowVehiclePhoto()
                                // Skip the system cover slide — LiveFollowMapView owns the expand.
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) {
                                    showLiveFollowMap = true
                                }
                            }
                        },
                        isRecordingCardVisible: tabSelection.selectedTab == .trips
                            && isRecordingCardInViewport
                            && !showLiveFollowMap
                    )
                    .id(activeTripID)
                    .onAppear { isRecordingCardInViewport = true }
                    .onDisappear { isRecordingCardInViewport = false }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listSectionSpacing(6)
            }

            if hasAnyTrips {
                Section {
                    TripListFiltersBar(
                        searchText: $searchText,
                        searchFocused: $isSearchFocused,
                        selectedDateSection: $selectedDateSection,
                        selectedCategoryID: $selectedCategoryID,
                        selectedVehicleFilter: $selectedVehicleFilter,
                        selectedPlaceID: $selectedPlaceID,
                        vehicles: vehicles,
                        places: places,
                        weekSummaryText: weekSummary
                    )
                    .background {
                        // Only the stop-credits slide needs this, and a `.global` frame
                        // changes every scroll frame — so don't install it otherwise.
                        if endCredits != nil {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: CreditsListLandingYKey.self,
                                    value: geo.frame(in: .global).maxY + 6
                                )
                            }
                        }
                    }
                }
                .glassListRow()
                .listRowInsets(
                    EdgeInsets(
                        top: 8,
                        leading: GlassTokens.listContentHorizontalInset,
                        bottom: 8,
                        trailing: GlassTokens.listContentHorizontalInset
                    )
                )
                .listSectionSpacing(6)
            }

            if visibleTrips.isEmpty {
                let showFilteredEmpty = hasActiveFilters && hasAnyTrips
                let showDefaultEmpty = !hasAnyTrips
                    && !recordingService.state.isActiveSession
                    && endCredits == nil
                    && coldOpenTripID == nil
                if showFilteredEmpty || showDefaultEmpty {
                    GlassEmptyState(
                        title: hasActiveFilters ? L10n.tripsEmptyFilteredTitle : L10n.tripsEmptyTitle,
                        systemImage: "car",
                        message: hasActiveFilters
                            ? L10n.tripsEmptyFilteredMessage
                            : L10n.tripsEmptyMessage,
                        bounceTrigger: hasActiveFilters
                    )
                    .glassListRow()
                    .transition(TrailhoundMotion.fadeScaleTransition(reduceMotion: reduceMotion))
                }
            } else {
                ForEach(groups, id: \.section) { group in
                    Section(group.section.title) {
                        ForEach(Array(group.trips.enumerated()), id: \.element.id) { index, trip in
                            // Keep the new trip hidden until the blue bar finishes sliding onto it.
                            if endCredits?.tripID != trip.id {
                                tripRow(for: trip, isFirst: trip.id == firstTripID)
                                    .glassRow(position: GlassRowPosition.index(index, in: group.trips.count))
                            }
                        }
                    }
                }
                .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: visibleTrips.count)
            }

            if hasMorePages {
                // Sits below the last section rather than on the last row, so a page whose rows
                // were all filtered out in memory still pulls the next one instead of dead-ending.
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .accessibilityLabel(L10n.string("trips.loading_more"))
                        .onAppear(perform: loadNextPage)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap(focus: $isSearchFocused)
        .fieldKeyboardAccessory(
            title: L10n.searchTrips,
            focusID: isSearchFocused ? AnyHashable(true) : nil,
            onDone: {
                isSearchFocused = false
                KeyboardDismiss.dismiss()
            }
        )
        .glassListChrome()
        // Tighter than the global glass default so banner/search cards sit like date→trip gaps.
        .listSectionSpacing(6)
        .onChange(of: searchText) { _, newValue in
            let pending = newValue
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, searchText == pending else { return }
                debouncedSearchText = pending
            }
        }
        .onPreferenceChange(CreditsListLandingYKey.self) { newY in
            guard endCredits != nil else { return }
            listLandingMinY = newY
        }
        .navigationDestination(for: Trip.self) { trip in
            TripDetailView(trip: trip)
        }
        .navigationDestination(isPresented: $showNotificationsList) {
            NotificationsListView()
        }
        .navigationTitle(showsActiveRecordingNavAffordance ? "" : "Trailhound")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshOrphans()
            notificationStore.reload()
        }
        .onAppear {
            debouncedSearchText = searchText
            refreshOrphans()
            refreshListAggregates()
            reloadTrips()
            careSummary.refresh(in: modelContext)
            beginColdOpenIfNeeded(onlyIfRecentlyStarted: true)
        }
        .onStoreSave {
            // Row identity must refresh before the next body pass or a deleted model crashes.
            reloadTrips()
            careSummary.refresh(in: modelContext)
            // Week summary is display-only — coalesce rapid saves (merge + post-process).
            aggregatesRefreshTask?.cancel()
            aggregatesRefreshTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                refreshListAggregates()
            }
        }
        .onChange(of: pageFilters) { _, _ in
            resetPagingAndReload()
        }
        .onChange(of: recordingService.state) { _, newState in
            if !newState.isActiveSession {
                refreshOrphans()
                coldOpenArmed = false
                coldOpenTripID = nil
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    showLiveFollowMap = false
                }
            }
        }
        .onChange(of: recordingService.state.isActiveSession) { wasActive, isActive in
            if isActive {
                // New recording must never be blocked by a stuck credits card.
                if endCredits != nil {
                    endCredits = nil
                }
            } else {
                isRecordingCardInViewport = true
            }
            if !wasActive, isActive, endCredits == nil {
                beginColdOpenIfNeeded()
                requestScrollToTop()
            }
            // Vehicle auto-stop (and other external stops) still get a light morph —
            // full credits play only for manual Stop.
            if wasActive, !isActive, endCredits == nil, morphingTripID == nil,
               let newest = newestCompletedTrip(),
               let endedAt = newest.endedAt,
               Date().timeIntervalSince(endedAt) < 2.5 {
                morphingTripID = newest.id
                clearMorphingTripSoon(delayMilliseconds: reduceMotion ? 50 : 280)
            }
        }
        .onChange(of: scrollToTopToken) { _, _ in
            performScrollToTop(scrollProxy: scrollProxy)
        }
        .alert(L10n.tripsMergeTitle, isPresented: $showMergeConfirm) {
            Button(L10n.actionMerge) {
                Task { await performMerge() }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.tripsMergeMessage(mergeSelection.count))
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isMergeMode {
                    Button(L10n.actionMerge) {
                        showMergeConfirm = true
                    }
                    .disabled(completedMergeSelectionCount < 2 || isMerging)
                } else if recordingService.state.isActiveSession, showsActiveRecordingNavAffordance {
                    Button {
                        TrailhoundHaptics.selection()
                        scrollToActiveTrip(scrollProxy: scrollProxy)
                    } label: {
                        HStack(spacing: 6) {
                            TripListActiveRecordingNavIcon(
                                isPaused: recordingService.state == .paused,
                                reduceMotion: reduceMotion
                            )
                            Text("Trailhound")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string("trips.active_recording.show"))
                    .accessibilityIdentifier("trips.active_recording.nav")
                } else if !recordingService.state.isActiveSession {
                    HStack(spacing: 4) {
                        if !vehicles.isEmpty {
                            RecordingVehiclePicker(
                                vehicles: vehicles,
                                selectedVehicleID: recordingService.activeRecordingVehicleID(from: vehicles),
                                onSelect: { recordingService.setRecordingVehicle($0) }
                            )
                        }
                        Button {
                            coldOpenArmed = true
                            if recordingService.startManualRecording(),
                               let tripID = recordingService.activeTripID {
                                coldOpenTripID = tripID
                                requestScrollToTop()
                            } else {
                                coldOpenArmed = false
                                coldOpenTripID = nil
                            }
                        } label: {
                            TrailhoundRunningHoundIcon(reduceMotion: reduceMotion)
                        }
                        .accessibilityLabel(L10n.string("action.start"))
                        .transition(.opacity)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isMergeMode {
                    Button(L10n.cancel) {
                        isMergeMode = false
                        mergeSelection.removeAll()
                    }
                    .disabled(isMerging)
                } else {
                    HStack(spacing: 16) {
                        Button { isMergeMode = true } label: {
                            Image(systemName: "arrow.triangle.merge")
                        }
                        .accessibilityLabel(L10n.actionMerge)

                        Button {
                            notificationStore.markAllRead()
                            showNotificationsList = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")
                                if notificationStore.unreadCount > 0 {
                                    Text("\(min(notificationStore.unreadCount, 99))")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(4)
                                        .background(Circle().fill(.red))
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        .accessibilityLabel(L10n.notificationsTitle)
                        .accessibilityIdentifier("trips.notifications")
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : TrailhoundMotion.recordingMorph, value: morphingTripID)
        .overlay {
            if isMerging {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(L10n.tripsMergeProgress)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .allowsHitTesting(true)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L10n.tripsMergeProgress)
                .zIndex(100)
            }
        }
        .overlay {
            if let endCredits {
                GeometryReader { geo in
                    let containerFrame = geo.frame(in: .global)
                    let anchor = pinnedCreditsCardAnchor
                    let startY = anchor.minY > 0
                        ? anchor.minY - containerFrame.minY
                        : 12
                    let xOffset = anchor.minX > 0
                        ? anchor.minX - containerFrame.minX
                        : 0

                    Group {
                        if anchor.width > 0 {
                            RecordingEndCreditsView(
                                snapshot: endCredits,
                                reduceMotion: reduceMotion,
                                onFinished: startCreditsSlideIntoList
                            )
                            .frame(width: anchor.width)
                        } else {
                            RecordingEndCreditsView(
                                snapshot: endCredits,
                                reduceMotion: reduceMotion,
                                onFinished: startCreditsSlideIntoList
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                        }
                    }
                    .id(endCredits.sessionID)
                    .offset(x: xOffset, y: startY + creditsSlideY)
                }
                .allowsHitTesting(false)
                .zIndex(50)
            }
        }
        .fullScreenCover(isPresented: $showLiveFollowMap) {
            LiveFollowMapView(
                vehiclePhoto: liveFollowVehiclePhoto,
                vehicleSystemImage: "car.fill",
                cardAnchor: liveFollowCardAnchor,
                onClose: {
                    // Cover presentation itself stays silent; reverse morph already finished.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showLiveFollowMap = false
                    }
                },
                onStop: { anchor in
                    // Instant dismiss — no reverse morph; end credits play on the list.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        showLiveFollowMap = false
                    }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(280))
                        beginEndCredits(cardAnchor: anchor)
                    }
                }
            )
            .presentationBackground(.clear)
            .transaction { $0.disablesAnimations = true }
            .environment(recordingService)
            .environment(AppServices.runtime.locationService)
            .environment(NetworkMonitor.shared)
        }
    }

    @MainActor
    private func prepareLiveFollowVehiclePhoto() async {
        let vehicleID = recordingService.activeRecordingVehicleID(from: vehicles)
        let fileName = vehicles.first(where: { $0.id == vehicleID })?.photoFileName
        guard let fileName, !fileName.isEmpty else {
            liveFollowVehiclePhoto = nil
            return
        }
        // Same asset as the recording card — no backdrop punch (that eats white vehicles).
        if let synced = VehiclePhotoStore.shared.imageSync(fileName: fileName) {
            liveFollowVehiclePhoto = synced
            return
        }
        if let loaded = await VehiclePhotoStore.shared.image(fileName: fileName) {
            liveFollowVehiclePhoto = loaded
        } else {
            liveFollowVehiclePhoto = nil
        }
    }

    @ViewBuilder
    private func tripRow(for trip: Trip, isFirst: Bool) -> some View {
        let isMorphing = morphingTripID == trip.id
        let vehicle = trip.vehicleID.flatMap { id in vehicles.first(where: { $0.id == id }) }
        Group {
            if isMergeMode {
                Button {
                    toggleMergeSelection(trip.id)
                } label: {
                    HStack {
                        Image(systemName: mergeSelection.contains(trip.id) ? "checkmark.circle.fill" : "circle")
                            .accessibilityLabel(mergeSelection.contains(trip.id) ? L10n.a11ySelected : L10n.a11yNotSelected)
                        TripRowView(
                            trip: trip,
                            places: places,
                            privacyRadius: settings.privacyRadiusMeters,
                            vehicle: vehicle,
                            morphNamespace: tripMorphNamespace,
                            morphID: morphingTripID,
                            emphasizeLanding: isMorphing
                        )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            } else {
                NavigationLink(value: trip) {
                    TripRowView(
                        trip: trip,
                        places: places,
                        privacyRadius: settings.privacyRadiusMeters,
                        vehicle: vehicle,
                        morphNamespace: tripMorphNamespace,
                        morphID: morphingTripID,
                        emphasizeLanding: isMorphing
                    )
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier(isFirst ? "trips.row.first" : "trips.row.\(trip.id.uuidString)")
                .buttonStyle(.plain)
            }
        }
        .matchedGeometryEffectIfAvailable(
            id: isMorphing ? trip.id : nil,
            namespace: tripMorphNamespace,
            isSource: false
        )
        .transition(.opacity)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteTrip(trip)
            } label: {
                Label(L10n.delete, systemImage: "trash")
            }
            .destructiveTint()
        }
        .swipeActions(edge: .leading) {
            Button {
                addToMergeSelection(trip.id)
            } label: {
                Label(L10n.actionMerge, systemImage: "arrow.triangle.merge")
            }
            .tint(.indigo)

            Menu {
                ForEach(categories) { category in
                    Button {
                        updateCategory(trip, categoryID: category.id.uuidString)
                    } label: {
                        Label(category.name, systemImage: category.systemImage)
                    }
                }
            } label: {
                Label(L10n.actionCategory, systemImage: "tag")
            }
            .tint(.orange)
        }
    }

    private func beginColdOpenIfNeeded(onlyIfRecentlyStarted: Bool = false) {
        guard endCredits == nil,
              recordingService.state.isActiveSession,
              let tripID = recordingService.activeTripID
        else { return }

        // Already armed for this trip.
        if coldOpenTripID == tripID, coldOpenArmed { return }

        if onlyIfRecentlyStarted {
            guard let startedAt = recordingService.recordingStartedAt,
                  Date().timeIntervalSince(startedAt) < 2.0
            else { return }
        }

        coldOpenArmed = true
        coldOpenTripID = tripID
    }

    private func finishColdOpen() {
        coldOpenArmed = false
        // Only clear once this trip's entrance finished — don't block a newer start.
        if let active = recordingService.activeTripID, coldOpenTripID == active {
            coldOpenTripID = nil
        } else if coldOpenTripID != nil, recordingService.activeTripID == nil {
            coldOpenTripID = nil
        }
    }

    private func beginEndCredits(cardAnchor: RecordingCardAnchor) {
        guard let tripID = recordingService.activeTripID else {
            recordingService.stopManualRecording()
            return
        }

        resetTripFiltersToAll()

        let activeVehicleID = recordingService.activeRecordingVehicleID(from: vehicles)
        let serviceDue = activeVehicleID.flatMap { vehicleID in
            VehicleCareDueCalculator.urgentServiceDue(for: vehicleID, from: schedules)
        }

        let snapshot = RecordingEndCreditsSnapshot(
            sessionID: UUID(),
            tripID: tripID,
            durationText: DateFormatters.formatDuration(recordingService.elapsedTime),
            distanceText: DateFormatters.formatDistance(recordingService.currentDistanceMeters),
            coordinates: recordingService.liveBreadcrumbCoordinates,
            showsServiceDue: serviceDue != nil,
            serviceIsOverdue: serviceDue?.state.isOverdue ?? false
        )

        morphingTripID = tripID
        coldOpenArmed = false
        coldOpenTripID = nil
        creditsSlideY = 0
        isCreditsSliding = false
        pinnedCreditsCardAnchor = cardAnchor

        if reduceMotion {
            recordingService.stopManualRecording()
            endCredits = nil
            clearMorphingTripSoon(delayMilliseconds: 50)
            return
        }

        endCredits = snapshot
        recordingService.stopManualRecording()

        let sessionID = snapshot.sessionID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if endCredits?.sessionID == sessionID, !isCreditsSliding {
                startCreditsSlideIntoList()
            }
        }
    }

    private func resetTripFiltersToAll() {
        guard selectedCategoryID != nil || selectedVehicleFilter != nil || selectedPlaceID != nil else { return }

        if reduceMotion {
            selectedCategoryID = nil
            selectedVehicleFilter = nil
            selectedPlaceID = nil
        } else {
            withAnimation(TrailhoundMotion.recordingMorph) {
                selectedCategoryID = nil
                selectedVehicleFilter = nil
                selectedPlaceID = nil
            }
        }
    }

    private func requestScrollToTop() {
        scrollToTopToken += 1
        scrollToTopRequest = TripListScrollToTopRequest(id: UUID())
    }

    private func performScrollToTop(scrollProxy: ScrollViewProxy) {
        let target = TripListScrollTarget.top
        let delays: [UInt64] = [0, 50, 140]
        Task { @MainActor in
            for (index, delay) in delays.enumerated() {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                var transaction = Transaction()
                transaction.disablesAnimations = index < delays.count - 1 || reduceMotion
                withTransaction(transaction) {
                    scrollProxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    private func scrollToActiveTrip(scrollProxy: ScrollViewProxy) {
        guard let tripID = recordingService.activeTripID else {
            requestScrollToTop()
            return
        }

        let delays: [UInt64] = [0, 50, 140]
        Task { @MainActor in
            for (index, delay) in delays.enumerated() {
                if delay > 0 {
                    try? await Task.sleep(for: .milliseconds(delay))
                }
                var transaction = Transaction()
                transaction.disablesAnimations = index < delays.count - 1 || reduceMotion
                withTransaction(transaction) {
                    scrollProxy.scrollTo(tripID, anchor: .top)
                }
            }
        }
    }

    private func startCreditsSlideIntoList() {
        guard endCredits != nil, !isCreditsSliding else { return }

        let startGlobal = pinnedCreditsCardAnchor.minY > 0
            ? pinnedCreditsCardAnchor.minY
            : 0
        let measured = listLandingMinY - startGlobal
        let distance = measured > 40 ? measured : 140

        isCreditsSliding = true

        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            creditsSlideY = distance
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(210))
            // Swap overlay → real row with no List insert morph / empty-cell fade.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                endCredits = nil
                creditsSlideY = 0
                isCreditsSliding = false
                pinnedCreditsCardAnchor = RecordingCardAnchor()
            }
            TrailhoundHaptics.selection()
            clearMorphingTripSoon(delayMilliseconds: 220)
        }
    }

    private func clearMorphingTripSoon(delayMilliseconds: Int = 280) {
        let clearingID = morphingTripID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            if morphingTripID == clearingID {
                morphingTripID = nil
            }
        }
    }

    private func refreshOrphans() {
        orphanTrips = TripRecoveryService.findOrphanTrips(in: modelContext)
        TripRecoveryService.scheduleOrphanStaleNotifications(
            in: modelContext,
            excludingTripID: recordingService.activeTripID
        )
    }

    private func toggleMergeSelection(_ id: UUID) {
        if mergeSelection.contains(id) {
            mergeSelection.remove(id)
        } else {
            mergeSelection.insert(id)
        }
    }

    private func addToMergeSelection(_ id: UUID) {
        isMergeMode = true
        mergeSelection.insert(id)
    }

    private func updateCategory(_ trip: Trip, categoryID: String) {
        trip.categoryID = categoryID
        try? modelContext.save()
    }

    private func deleteTrip(_ trip: Trip) {
        TrailhoundHaptics.destructive()
        TripMapSnapshotCache.shared.remove(for: trip.id)
        TripRoutePathCache.shared.remove(for: trip.id)
        TripRollupService.remove(trip, in: modelContext)
        modelContext.delete(trip)
        mergeSelection.remove(trip.id)
        try? modelContext.save()
        ToastPresenter.shared.show(.deleted, playHaptic: false)
    }

    private func performMerge() async {
        guard !isMerging else { return }
        TrailhoundHaptics.selection()
        isMerging = true
        defer { isMerging = false }

        // Fetched by ID rather than filtered from the loaded pages: a selection made before
        // scrolling could otherwise include trips that are no longer resident.
        let selectedIDs = Array(mergeSelection)
        let container = modelContext.container
        do {
            let mergedUUID = try await TripMergeService.merge(
                tripIDs: selectedIDs,
                container: container
            )
            let legCount = selectedIDs.count
            isMergeMode = false
            mergeSelection.removeAll()
            ToastPresenter.shared.show(.tripsMerged)
            if !UITestSupport.isUnitTesting {
                TripNotificationService.notifyTripsMerged(
                    tripID: mergedUUID,
                    legCount: legCount
                )
            }
            Task { @MainActor in
                await TripPostProcessor.process(
                    tripUUID: mergedUUID,
                    container: container
                )
            }
        } catch let error as TripMergeError {
            modelContext.rollback()
            AppErrorPresenter.shared.presentInfo(error.localizedDescription)
        } catch {
            modelContext.rollback()
            AppErrorPresenter.shared.present(error.localizedDescription)
        }
    }
}

private struct TripListActiveRecordingNavIcon: View {
    var isPaused: Bool
    var reduceMotion: Bool

    @State private var steeringTilt: Double = 0

    private var accent: Color {
        isPaused ? TrailhoundBrandColors.paused : TrailhoundBrandColors.recording
    }

    private let badgeSize: CGFloat = 30
    /// Tightens the optical gap to the title next to it; the glyph itself is already centered
    /// in its layout box.
    private let glyphNudge = CGSize(width: 3, height: 0.35)
    private let maxTilt: Double = 55
    private let swingDuration: Double = 2.4

    var body: some View {
        Image(systemName: "steeringwheel")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accent)
            // Must stay inside the frame and nudge below. Applied outside them, the anchor is
            // the badge center while the glyph has been moved away from it, so the wheel
            // orbits that point instead of spinning in place.
            .rotationEffect(.degrees(steeringTilt))
            .frame(width: badgeSize, height: badgeSize)
            .offset(glyphNudge)
            .accessibilityHidden(true)
            .task(id: wobbleTaskID) {
                await runSteeringWobble()
            }
    }

    private var wobbleTaskID: String {
        "\(isPaused)-\(reduceMotion)"
    }

    @MainActor
    private func runSteeringWobble() async {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { steeringTilt = 0 }

        guard !isPaused, !reduceMotion else { return }

        // Half-length intro: leaving neutral covers half the travel of a full swing, so at the
        // same duration the very first swing read slower than every one after it.
        withAnimation(.easeOut(duration: swingDuration / 2)) {
            steeringTilt = maxTilt
        }
        try? await Task.sleep(for: .seconds(swingDuration / 2))
        guard !Task.isCancelled else { return }

        // One repeating animation instead of a sleep loop: no periodic main-actor wake-ups and
        // no drift between the sleep and the animation clock.
        withAnimation(.easeInOut(duration: swingDuration).repeatForever(autoreverses: true)) {
            steeringTilt = -maxTilt
        }
    }
}

private enum TripListScrollTarget: Hashable {
    case top
}

private struct TripListScrollToTopRequest: Equatable {
    let id: UUID
}

/// UIKit fallback — iOS 17+ `List` is backed by `UICollectionView`, not `UITableView`.
private struct TripListScrollToTopInstaller: UIViewRepresentable {
    var request: TripListScrollToTopRequest?

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var handledRequestID: UUID?
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let request else { return }
        guard context.coordinator.handledRequestID != request.id else { return }
        context.coordinator.handledRequestID = request.id
        scheduleScrollToTop(from: uiView)
    }

    private func scheduleScrollToTop(from view: UIView) {
        let delays: [TimeInterval] = [0, 0.05, 0.14]
        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let animated = index == delays.count - 1
                scrollLinkedListToTop(from: view, animated: animated)
            }
        }
    }

    private func scrollLinkedListToTop(from view: UIView, animated: Bool) {
        let scrollView = view.enclosingListScrollView ?? view.window?.largestVerticalScrollView
        scrollView?.forceScrollToTop(animated: animated)
    }
}

private extension UIScrollView {
    func forceScrollToTop(animated: Bool) {
        if let tableView = self as? UITableView,
           tableView.numberOfSections > 0,
           tableView.numberOfRows(inSection: 0) > 0 {
            tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: animated)
        } else if let collectionView = self as? UICollectionView,
                  collectionView.numberOfSections > 0,
                  collectionView.numberOfItems(inSection: 0) > 0 {
            collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: animated)
        }

        let top = CGPoint(x: 0, y: -adjustedContentInset.top)
        setContentOffset(top, animated: animated)
    }
}

private extension UIView {
    var enclosingListScrollView: UIScrollView? {
        var current: UIView? = self
        while let view = current {
            if let collectionView = view as? UICollectionView { return collectionView }
            if let tableView = view as? UITableView { return tableView }
            current = view.superview
        }
        return nil
    }

    var allSubviewsRecursive: [UIView] {
        subviews + subviews.flatMap(\.allSubviewsRecursive)
    }
}

private extension UIWindow {
    var largestVerticalScrollView: UIScrollView? {
        allSubviewsRecursive
            .compactMap { $0 as? UIScrollView }
            .filter { $0.contentSize.height > $0.bounds.height }
            .max(by: { $0.contentSize.height < $1.contentSize.height })
    }
}

private struct CreditsListLandingYKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    NavigationStack { TripListView() }
        .modelContainer(PreviewData.shared.container)
        .environment(PreviewData.shared.recordingService)
}
