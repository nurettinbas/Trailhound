import SwiftData
import SwiftUI

struct TripListView: View {
    @Query(sort: \Trip.startedAt, order: .reverse) private var allTrips: [Trip]

    /// In-memory filter — `#Predicate` on `@Model` key paths is not Swift 6 `Sendable`-safe.
    private var trips: [Trip] {
        allTrips.filter { $0.endedAt != nil }
    }
    @Query private var places: [SavedPlace]
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Query private var vehicles: [VehicleProfile]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(TripRecordingService.self) private var recordingService
    @Bindable private var settings = AppSettings.shared

    @Bindable private var notificationStore = AppNotificationStore.shared

    @State private var selectedLabel: String?
    @State private var selectedCategoryID: String?
    @State private var selectedDateSection: TripDateSection?
    @State private var mergeSelection = Set<UUID>()
    @State private var isMergeMode = false
    @Bindable private var tabSelection = TabSelection.shared

    @State private var orphanTrips: [TripRecoveryService.OrphanTrip] = []
    @State private var showMergeConfirm = false
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
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

    private var hasActiveFilters: Bool {
        selectedLabel != nil
            || selectedCategoryID != nil
            || selectedDateSection != nil
            || !debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var completedTrips: [Trip] {
        trips.filter { trip in
            if let selectedLabel, trip.label != selectedLabel { return false }
            if let selectedCategoryID, trip.categoryID != selectedCategoryID { return false }
            if let selectedDateSection,
               TripDateGrouping.section(for: trip.startedAt) != selectedDateSection {
                return false
            }
            if !TripListViewModel.matchesSearch(
                trip,
                searchText: debouncedSearchText,
                places: places,
                privacyRadius: settings.privacyRadiusMeters
            ) {
                return false
            }
            return true
        }
    }

    private var groupedTrips: [(section: TripDateSection, trips: [Trip])] {
        TripDateGrouping.groupedSections(from: completedTrips)
    }

    private var weekSummaryText: String {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekTrips = StatsViewModel.trips(
            in: DateInterval(start: weekAgo, end: Date()),
            from: trips
        )
        let stats = StatsViewModel.stats(for: weekTrips)
        return L10n.weekSummary(
            distance: stats.totalDistanceText,
            duration: stats.totalDurationText
        )
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

    @ViewBuilder
    private func tripList(scrollProxy: ScrollViewProxy) -> some View {
        List {
            Section {
                LocationPermissionBanner()
                    .id(TripListScrollTarget.top)
                    .background {
                        TripListScrollToTopInstaller(request: scrollToTopRequest)
                    }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

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
                                    refreshOrphans()
                                }
                            }
                            .buttonStyle(.bordered)
                            Button(L10n.delete, role: .destructive) {
                                if TripRecoveryService.deleteOrphan(orphan.trip, in: modelContext) {
                                    refreshOrphans()
                                }
                            }
                            .destructiveTint()
                        }
                    }
                }
                .glassListRow()
            }

            if recordingService.state.isActiveSession,
               endCredits == nil,
               let activeTripID = recordingService.activeTripID {
                Section {
                    ActiveTripView(
                        morphNamespace: tripMorphNamespace,
                        morphID: activeTripID,
                        playEntranceReveal: false,
                        onEntranceFinished: finishColdOpen,
                        onStop: { anchor in beginEndCredits(cardAnchor: anchor) },
                        isRecordingCardVisible: tabSelection.selectedTab == .trips && isRecordingCardInViewport
                    )
                    .id(activeTripID)
                    .onAppear { isRecordingCardInViewport = true }
                    .onDisappear { isRecordingCardInViewport = false }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if !trips.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.sectionThisWeek)
                                .font(.subheadline.weight(.semibold))
                            Text(weekSummaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .numericTextAnimation(value: weekSummaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(L10n.sectionThisWeek). \(weekSummaryText)")
                }
                .glassListRow()
            }

            if !trips.isEmpty {
                Section {
                    TripListFiltersBar(
                        searchText: $searchText,
                        selectedDateSection: $selectedDateSection,
                        selectedCategoryID: $selectedCategoryID
                    )
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: CreditsListLandingYKey.self,
                                value: geo.frame(in: .global).maxY + 6
                            )
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if completedTrips.isEmpty {
                let showFilteredEmpty = hasActiveFilters && !trips.isEmpty
                let showDefaultEmpty = trips.isEmpty
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
                ForEach(groupedTrips, id: \.section) { group in
                    Section(group.section.title) {
                        ForEach(Array(group.trips.enumerated()), id: \.element.id) { index, trip in
                            // Keep the new trip hidden until the blue bar finishes sliding onto it.
                            if endCredits?.tripID != trip.id {
                                tripRow(for: trip)
                                    .glassRow(position: GlassRowPosition.index(index, in: group.trips.count))
                            }
                        }
                    }
                }
                .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: completedTrips.count)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .listSectionSpacing(12)
        .glassListChrome()
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
            beginColdOpenIfNeeded(onlyIfRecentlyStarted: true)
        }
        .onChange(of: recordingService.state) { _, newState in
            if !newState.isActiveSession {
                refreshOrphans()
                coldOpenArmed = false
                coldOpenTripID = nil
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
               let newest = completedTrips.first,
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
            Button(L10n.actionMerge) { performMerge() }
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
                    .disabled(mergeSelection.count < 2)
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
                    HStack(spacing: 8) {
                        if !vehicles.isEmpty {
                            RecordingVehiclePicker(
                                vehicles: vehicles,
                                selectedVehicleID: recordingService.activeRecordingVehicleID(in: modelContext),
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
                        HStack(spacing: 6) {
                            Image(systemName: "record.circle")
                            Text(L10n.string("action.start"))
                        }
                    }
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
    }

    @ViewBuilder
    private func tripRow(for trip: Trip) -> some View {
        let isMorphing = morphingTripID == trip.id
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
                        morphNamespace: tripMorphNamespace,
                        morphID: morphingTripID,
                        emphasizeLanding: isMorphing
                    )
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier(completedTrips.first?.id == trip.id ? "trips.row.first" : "trips.row.\(trip.id.uuidString)")
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

        let snapshot = RecordingEndCreditsSnapshot(
            sessionID: UUID(),
            tripID: tripID,
            durationText: DateFormatters.formatDuration(recordingService.elapsedTime),
            distanceText: DateFormatters.formatDistance(recordingService.currentDistanceMeters),
            coordinates: recordingService.liveBreadcrumbCoordinates
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
        guard selectedCategoryID != nil else { return }

        if reduceMotion {
            selectedCategoryID = nil
        } else {
            withAnimation(TrailhoundMotion.recordingMorph) {
                selectedCategoryID = nil
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
        modelContext.delete(trip)
        mergeSelection.remove(trip.id)
        try? modelContext.save()
    }

    private func performMerge() {
        TrailhoundHaptics.selection()
        let selected = completedTrips.filter { mergeSelection.contains($0.id) }
        do {
            if let merged = try TripMergeService.merge(trips: selected, into: modelContext) {
                let tripUUID = merged.id
                let container = modelContext.container
                Task { @MainActor in
                    await TripPostProcessor.process(
                        tripUUID: tripUUID,
                        container: container
                    )
                }
            }
            isMergeMode = false
            mergeSelection.removeAll()
        } catch {
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
    /// SF Symbol steering wheel sits left of its layout box — nudge right for optical center.
    private let glyphOpticalOffset = CGSize(width: 3, height: 0.35)

    var body: some View {
        Image(systemName: "steeringwheel")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: badgeSize, height: badgeSize)
            .offset(glyphOpticalOffset)
            .rotationEffect(.degrees(steeringTilt), anchor: .center)
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
        steeringTilt = 0
        guard !isPaused, !reduceMotion else { return }

        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 3.5)) {
                steeringTilt = 55
            }
            try? await Task.sleep(for: .milliseconds(3500))
            guard !Task.isCancelled else { break }
            withAnimation(.easeInOut(duration: 3.5)) {
                steeringTilt = -55
            }
            try? await Task.sleep(for: .milliseconds(3500))
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
