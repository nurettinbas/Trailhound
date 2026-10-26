import SwiftData
import SwiftUI
import UIKit

struct NotificationsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TripRecordingService.self) private var recordingService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query private var vehicles: [VehicleProfile]
    @Query private var schedules: [VehicleSchedule]
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Bindable private var store = AppNotificationStore.shared
    @Bindable private var tabSelection = TabSelection.shared
    @Environment(\.trailhoundLayout) private var layout
    @State private var roadVehiclePhoto: UIImage?
    @State private var selectedNotificationID: UUID?

    var body: some View {
        inboxRoot
            .navigationTitle(L10n.notificationsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    GlassToolbarCircleButton(systemName: "xmark") {
                        tabSelection.closeNotifications()
                    }
                    .accessibilityLabel(L10n.cancel)
                }
                .hideSharedToolbarBackgroundIfAvailable()
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(L10n.notificationsMarkAllRead) {
                            store.markAllRead()
                            ToastPresenter.shared.show(.saved)
                        }
                        .disabled(store.unreadCount == 0)
                        Button(L10n.notificationsClearAll, role: .destructive) {
                            DeleteConfirmPresenter.shared.confirm(.notificationsAll) {
                                store.clearAll()
                                ToastPresenter.shared.show(.deleted)
                            }
                        }
                        .disabled(store.items.isEmpty)
                    } label: {
                        GlassToolbarSymbol(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                store.reload()
                if selectedNotificationID == nil {
                    selectedNotificationID = store.items.first?.id
                }
            }
            .onChange(of: store.items.map(\.id)) { _, ids in
                guard let selectedNotificationID, !ids.contains(selectedNotificationID) else { return }
                self.selectedNotificationID = ids.first
            }
    }

    @ViewBuilder
    private var inboxRoot: some View {
        switch layout.layoutClass {
        case .phone:
            inboxList()
        case .duoOpen:
            notificationSplit
        case .phoneLandscape where layout.isPhoneBook:
            notificationSplit
        case .phoneLandscape, .pad:
            HStack(spacing: GlassTokens.hingeGutter) {
                notificationRail
                    .frame(width: layout.layoutClass == .pad && !layout.isLandscape ? 280 : nil)
                    .frame(maxWidth: layout.showsHeroRail ? nil : 320)
                inboxList()
            }
        }
    }

    private var notificationSplit: some View {
        TrailhoundPaneSplit {
            inboxList(paintsAtmosphere: false)
        } focus: {
            notificationPreview
        }
    }

    /// Open book and a wide landscape phone. A row selects the notice; Open leaves the inbox.
    private var usesSplitInbox: Bool {
        layout.layoutClass == .duoOpen || layout.isPhoneBook
    }

    private var notificationRail: some View {
        VStack(alignment: .leading, spacing: 16) {
            TrailhoundHeroRail(collapsed: false) {
                Text(L10n.notificationsTitle)
            } figure: {
                Text("\(store.unreadCount)")
            } detail: {
                Text(L10n.notificationsEmptyMessage)
            }
            Button(L10n.notificationsMarkAllRead) {
                store.markAllRead()
                ToastPresenter.shared.show(.saved)
            }
            .trailhoundGlassButton()
            .disabled(store.unreadCount == 0)
            Spacer(minLength: 0)
        }
        .padding(20)
        .trailhoundPaneCard()
    }

    private var selectedNotification: StoredAppNotification? {
        store.items.first(where: { $0.id == selectedNotificationID }) ?? store.items.first
    }

    private var notificationPreview: some View {
        ScrollView {
            if let item = selectedNotification {
                previewCard(item)
                    .padding(16)
            } else {
                GlassEmptyState(
                    title: L10n.notificationsEmptyTitle,
                    systemImage: "bell.slash",
                    message: L10n.notificationsEmptyMessage
                )
                .frame(maxWidth: .infinity, minHeight: 280)
            }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func previewCard(_ item: StoredAppNotification) -> some View {
        let kind = store.kind(for: item)
        let trip = resolvedTrip(for: item)
        let showsOpen = store.route(for: item).opensDestination
            || (item.tripID != nil && Self.linksToTrip(kind))
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: kind.systemImage)
                    .font(.title2)
                    .foregroundStyle(tint(for: kind, body: item.body))
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.title3.weight(.semibold))
                        .glassPrimaryInk()
                    Text(previewWhen(item, trip: trip))
                        .font(.subheadline)
                        .glassSecondaryInk()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let trip {
                Text(TripListViewModel.routeSummary(for: trip))
                    .font(.body.weight(.medium))
                    .glassPrimaryInk()
                previewMetrics(for: trip)
                previewFacts(for: trip)
            } else {
                Text(item.body)
                    .font(.body)
                    .glassSecondaryInk()
            }

            if showsOpen {
                Button(L10n.notificationsOpen) {
                    open(item)
                }
                .trailhoundProminentButton()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private func previewMetrics(for trip: Trip) -> some View {
        let distance = trip.distanceMeters > 0 ? TripListViewModel.distanceText(for: trip) : nil
        let duration = TripListViewModel.durationText(for: trip)
        let durationText = duration == "—" ? nil : duration
        let speed = TripListViewModel.averageSpeedText(for: trip)
        if distance != nil || durationText != nil || speed != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    metricChipRow(distance: distance, duration: durationText, speed: speed)
                }
                VStack(alignment: .leading, spacing: 8) {
                    metricChipRow(distance: distance, duration: durationText, speed: speed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func metricChipRow(distance: String?, duration: String?, speed: String?) -> some View {
        if let distance {
            MetricChip(value: distance, systemImage: "road.lanes")
        }
        if let duration {
            MetricChip(value: duration, systemImage: "clock")
        }
        if let speed {
            MetricChip(value: speed, systemImage: "speedometer")
        }
    }

    private struct MetricChip: View {
        var value: String
        var systemImage: String

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .glassSecondaryInk()
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .glassPrimaryInk()
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassNestedChoice(isSelected: false)
            .fixedSize(horizontal: true, vertical: true)
        }
    }

    @ViewBuilder
    private func previewFacts(for trip: Trip) -> some View {
        let vehicle = trip.vehicleID.flatMap { id in vehicles.first(where: { $0.id == id }) }
        let category = categoryName(for: trip)
        let maxSpeed = TripListViewModel.maxSpeedLabel(for: trip)
        let fuel = TripListViewModel.fuelText(for: trip)
        if vehicle != nil || category != nil || maxSpeed != nil || fuel != nil || trip.note?.isEmpty == false {
            VStack(alignment: .leading, spacing: 6) {
                if let vehicle {
                    previewFact(systemImage: "car", text: vehicle.name)
                }
                if let category {
                    previewFact(systemImage: "tag", text: category)
                }
                if let maxSpeed {
                    previewFact(systemImage: "speedometer", text: maxSpeed)
                }
                if let fuel {
                    previewFact(systemImage: "fuelpump", text: fuel)
                }
                if let note = trip.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .glassSecondaryInk()
                }
            }
        }
    }

    private func previewFact(systemImage: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption)
                .glassSecondaryInk()
                .frame(width: 16)
            Text(text)
                .font(.subheadline)
                .glassPrimaryInk()
        }
    }

    private func previewWhen(_ item: StoredAppNotification, trip: Trip?) -> String {
        let relative = relativeDate(item.createdAt)
        if let trip {
            return "\(relative) · \(TripListViewModel.dateText(for: trip))"
        }
        let clock = DateFormatters.tripDateFormatter().string(from: item.createdAt)
        return "\(relative) · \(clock)"
    }

    private func categoryName(for trip: Trip) -> String? {
        if let match = categories.first(where: { $0.id.uuidString == trip.categoryID }) {
            return match.name
        }
        if trip.categoryID == BuiltInCategory.businessID.uuidString {
            return L10n.categoryBusiness
        }
        if trip.categoryID == BuiltInCategory.personalID.uuidString {
            return L10n.categoryPersonal
        }
        return nil
    }

    @ViewBuilder
    private func inboxList(paintsAtmosphere: Bool = true) -> some View {
        Group {
            if store.items.isEmpty && !recordingService.state.isActiveSession {
                GlassEmptyState(
                    title: L10n.notificationsEmptyTitle,
                    systemImage: "bell.slash",
                    message: L10n.notificationsEmptyMessage
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassListChrome(showsAtmosphere: paintsAtmosphere)
            } else {
                List {
                    if recordingService.state.isActiveSession {
                        Section {
                            activeRecordingCard
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }

                    ForEach(store.items) { item in
                        notificationRow(item)
                            .glassCard(contentInset: 12)
                            // Unread tint on the full card — never as an inner content background
                            // (that created a smaller second layer inside the glass).
                            .overlay {
                                let selected = usesSplitInbox && item.id == selectedNotificationID
                                if !item.isRead || selected {
                                    RoundedRectangle(cornerRadius: GlassTokens.cardRadius, style: .continuous)
                                        .fill(shellPalette.tintColor(for: colorScheme).opacity(selected ? 0.16 : 0.10))
                                        .allowsHitTesting(false)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .confirmingDeleteSwipe {
                                store.delete(item.id)
                                ToastPresenter.shared.show(.deleted)
                            }
                    }
                }
                .listStyle(.plain)
                .glassListChrome(showsAtmosphere: paintsAtmosphere)
            }
        }
    }

    private var recordingVehicle: VehicleProfile? {
        let id = recordingService.activeRecordingVehicleID(from: vehicles)
        guard let id else { return nil }
        return vehicles.first(where: { $0.id == id })
    }

    private var roadPhotoIdentity: String {
        let id = recordingVehicle?.id.uuidString ?? "none"
        let file = recordingVehicle?.photoFileName ?? "none"
        // Epoch forces reload when Observation misses nested SwiftData vehicleID mutations.
        return "\(id)|\(file)|\(recordingService.recordingVehicleEpoch)"
    }

    private var urgentServiceDue: VehicleDueItem? {
        guard let vehicleID = recordingService.activeRecordingVehicleID(from: vehicles) else {
            return nil
        }
        return VehicleCareDueCalculator.urgentServiceDue(for: vehicleID, from: schedules)
    }

    private var activeRecordingCard: some View {
        NotificationActiveRecordingCard(
            recordingService: recordingService,
            roadVehiclePhoto: roadVehiclePhoto,
            roadPhotoIdentity: roadPhotoIdentity,
            liveSessionBody: liveSessionBody,
            urgentServiceDue: urgentServiceDue,
            onLoadPhoto: { await loadRoadVehiclePhoto() },
            onStop: { recordingService.stopManualRecording() }
        )
    }

    private var liveSessionBody: String {
        let duration = DateFormatters.formatDuration(recordingService.elapsedTime)
        let distance = DateFormatters.formatDistance(recordingService.currentDistanceMeters)
        if recordingService.state == .paused {
            return "\(duration) · \(distance)"
        }
        let speed = L10n.formatSpeedKmh(max(0, recordingService.currentSpeedMps) * 3.6)
        return "\(duration) · \(distance) · \(speed)"
    }

    private func leaveInbox(_ action: () -> Void) {
        tabSelection.closeNotifications()
        action()
    }

    private func select(_ item: StoredAppNotification) {
        selectedNotificationID = item.id
        if !item.isRead {
            store.markRead(item.id)
        }
    }

    private func open(_ item: StoredAppNotification) {
        store.markRead(item.id)
        selectedNotificationID = item.id
        let kind = store.kind(for: item)
        if let tripID = item.tripID, Self.linksToTrip(kind) {
            switch TripDeepLinkResolver.resolve(
                tripID: tripID,
                in: modelContext,
                activeTripID: recordingService.activeTripID
            ) {
            case .missing:
                ToastPresenter.shared.show(.tripNotFound)
            case .unfinished:
                break
            case .recording:
                leaveInbox { tabSelection.focusRecordingCard() }
            case .finished:
                leaveInbox { tabSelection.openTrip(id: tripID) }
            }
            return
        }
        let route = store.route(for: item)
        guard route.opensDestination else { return }
        leaveInbox { route.perform() }
    }

    private static func linksToTrip(_ kind: AppNotificationKind) -> Bool {
        switch kind {
        case .tripStarted, .tripEnded, .tripsMerged:
            return true
        default:
            return false
        }
    }

    private func loadRoadVehiclePhoto() async {
        let fileName = recordingVehicle?.photoFileName
        guard let fileName, !fileName.isEmpty else {
            roadVehiclePhoto = nil
            return
        }
        let image: UIImage?
        if let synced = VehiclePhotoStore.shared.imageSync(fileName: fileName) {
            image = synced
        } else {
            image = await VehiclePhotoStore.shared.image(fileName: fileName)
        }
        guard recordingVehicle?.photoFileName == fileName else { return }
        roadVehiclePhoto = image
    }

    @ViewBuilder
    private func notificationRow(_ item: StoredAppNotification) -> some View {
        let kind = store.kind(for: item)
        let trip = resolvedTrip(for: item)
        let showsOrphanActions = kind == .orphanStale
            && trip?.endedAt == nil
            && trip?.id != recordingService.activeTripID
        let opensTrip = Self.linksToTrip(kind) && item.tripID != nil && !showsOrphanActions
        let route = store.route(for: item)
        let opensRoute = !opensTrip && route.opensDestination && !showsOrphanActions
        let choosesPreview = usesSplitInbox

        VStack(alignment: .leading, spacing: 6) {
            if opensTrip || opensRoute {
                rowContent(item: item, kind: kind, trip: trip, showsChevron: !choosesPreview)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if choosesPreview {
                            select(item)
                        } else {
                            open(item)
                        }
                    }
            } else {
                rowContent(item: item, kind: kind, trip: trip, showsChevron: false)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if choosesPreview {
                            select(item)
                        } else {
                            store.markRead(item.id)
                        }
                    }
            }

            if showsOrphanActions, let trip {
                HStack(spacing: 10) {
                    Button {
                        store.markRead(item.id)
                        TripRecoveryService.resumeOrphan(trip, recordingService: recordingService)
                        store.reload()
                    } label: {
                        Label(L10n.resume, systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .trailhoundProminentButton()

                    Button(role: .destructive) {
                        DeleteConfirmPresenter.shared.confirm(.generic) {
                            if TripRecoveryService.deleteOrphan(trip, in: modelContext) {
                                store.delete(item.id)
                                store.reload()
                                ToastPresenter.shared.show(.deleted)
                            }
                        }
                    } label: {
                        Label(L10n.delete, systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .trailhoundProminentButton()
                    .destructiveTint()
                }
                .padding(.leading, 40)
            }
        }
    }

    private func rowContent(
        item: StoredAppNotification,
        kind: AppNotificationKind,
        trip: Trip?,
        showsChevron: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.systemImage)
                .font(.body)
                .foregroundStyle(tint(for: kind, body: item.body))
                .frame(width: 22, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(item.isRead ? .medium : .semibold))
                        .glassPrimaryInk()
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(relativeDate(item.createdAt))
                        .font(.caption2)
                        .glassSecondaryInk()
                        .layoutPriority(1)
                }

                Text(rowSubtitle(item: item, kind: kind, trip: trip))
                    .font(.caption)
                    .glassSecondaryInk()
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let meta = rowMeta(kind: kind, trip: trip) {
                    Text(meta)
                        .font(.caption2.weight(.medium))
                        .glassSecondaryInk()
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .glassDisclosureInk()
                    .frame(height: 20)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// Place names when the trip is still saved. The stored body keeps the coordinates from the moment it was written.
    private func rowSubtitle(item: StoredAppNotification, kind: AppNotificationKind, trip: Trip?) -> String {
        guard let trip else { return item.body }
        switch kind {
        case .tripStarted:
            return TripListViewModel.displayName(
                placeName: trip.startPlaceName,
                address: trip.startAddress,
                coordinate: trip.startCoordinate,
                places: [],
                privacyRadius: AppSettings.shared.privacyRadiusMeters
            )
        case .tripEnded, .tripsMerged:
            return TripListViewModel.routeSummary(
                for: trip,
                privacyRadius: AppSettings.shared.privacyRadiusMeters
            )
        default:
            return item.body
        }
    }

    private func rowMeta(kind: AppNotificationKind, trip: Trip?) -> String? {
        guard let trip, kind == .tripEnded || kind == .tripsMerged else { return nil }
        let distance = TripListViewModel.distanceText(for: trip)
        let duration = TripListViewModel.durationText(for: trip)
        guard trip.distanceMeters > 0 || duration != "—" else { return nil }
        if duration == "—" { return distance }
        if trip.distanceMeters <= 0 { return duration }
        return "\(distance) · \(duration)"
    }

    private func tint(for kind: AppNotificationKind, body: String = "") -> Color {
        switch kind {
        case .tripStarted: .green
        case .tripEnded: .blue
        case .tripDiscarded: .gray
        case .tripsMerged: .blue
        case .orphanStale: .orange
        case .recordingStopped: .red
        case .pairingSuggestion: .blue
        case .achievementUnlocked: Color(red: 0.85, green: 0.65, blue: 0.18)
        case .yearRecapReady: Color(red: 0.62, green: 0.42, blue: 0.86)
        case .vehicleCareReminder:
            isVehicleCareOverdue(body) ? .red : .orange
        }
    }

    private func isVehicleCareOverdue(_ body: String) -> Bool {
        let lower = body.lowercased()
        return lower.contains("overdue") || lower.contains("vadesi geçti")
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = DateFormatters.currentLocale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func resolvedTrip(for item: StoredAppNotification) -> Trip? {
        guard let tripID = item.tripID else { return nil }
        if let match = trips.first(where: { $0.id == tripID }) {
            return match
        }
        let targetID = tripID
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate<Trip> { trip in
                trip.id == targetID
            }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}

/// Isolated recording card — playback uses a sliding switch (not system bordered morph).
private struct NotificationActiveRecordingCard: View {
    let recordingService: TripRecordingService
    let roadVehiclePhoto: UIImage?
    let roadPhotoIdentity: String
    let liveSessionBody: String
    var urgentServiceDue: VehicleDueItem? = nil
    let onLoadPhoto: () async -> Void
    let onStop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Optimistic chrome — drives the switch thumb before service work finishes.
    @State private var displayedPaused: Bool = false

    var body: some View {
        let isPaused = displayedPaused

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(isPaused ? L10n.recordingPaused : L10n.recordingStarted)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Image(systemName: isPaused ? "pause.circle.fill" : "record.circle.fill")
                    .font(.title3)
                    .foregroundStyle(isPaused ? Color.yellow : GlassSemantic.notificationBadge)
                    .compositingGroup()
                    .accessibilityHidden(true)
            }
            .animation(nil, value: isPaused)

            RecordingCarAnimationView(
                compact: true,
                isAnimating: true,
                isPaused: isPaused,
                systemImage: VehicleIconOption.default.rawValue,
                vehiclePhoto: roadVehiclePhoto,
                symbolScaleX: -1,
                allowsVerticalBounce: false
            ) { layout in
                if let serviceDue = urgentServiceDue {
                    RecordingVehicleServiceBadge(
                        carSize: layout.carSize,
                        isOverdue: serviceDue.state.isOverdue
                    )
                    .recordingVehicleServiceBadgePosition(layout: layout)
                }
            }
            .transaction { $0.disablesAnimations = true }
            .task(id: roadPhotoIdentity) {
                await onLoadPhoto()
            }

            Text(liveSessionBody)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .monospacedDigit()
                .animation(nil, value: isPaused)

            HStack(spacing: 10) {
                NotificationPlaybackSwitch(
                    isPaused: isPaused,
                    reduceMotion: reduceMotion,
                    onToggle: togglePlayback
                )

                Button(role: .destructive, action: onStop) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                        Text(L10n.stop)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .trailhoundDestructiveButton()
            }
        }
        .padding(14)
        .background {
            RecordingCardStyle.glassSurface(isPaused: isPaused)
        }
        .animation(nil, value: isPaused)
        .clipShape(RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .onAppear {
            displayedPaused = recordingService.state == .paused
        }
        .onChange(of: recordingService.state) { _, newState in
            let paused = newState == .paused
            guard paused != displayedPaused else { return }
            if reduceMotion {
                displayedPaused = paused
            } else {
                withAnimation(TrailhoundMotion.recordingToggle) {
                    displayedPaused = paused
                }
            }
        }
    }

    private func togglePlayback() {
        let nextPaused = !displayedPaused
        if reduceMotion {
            displayedPaused = nextPaused
        } else {
            withAnimation(TrailhoundMotion.recordingToggle) {
                displayedPaused = nextPaused
            }
        }
        if nextPaused {
            recordingService.pauseRecording()
        } else {
            recordingService.resumeRecording()
        }
    }
}

/// Sliding Pause | Resume control — thumb moves; icons stay put (obvious, fast, not a text morph).
private struct NotificationPlaybackSwitch: View {
    let isPaused: Bool
    let reduceMotion: Bool
    let onToggle: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 3
            let thumbWidth = (geo.size.width - inset * 2) / 2

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))

                Capsule(style: .continuous)
                    .fill(shellPalette.glassReadabilityTint(for: colorScheme))
                    .frame(width: thumbWidth, height: geo.size.height - inset * 2)
                    .offset(x: inset + (isPaused ? thumbWidth : 0))
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)

                HStack(spacing: 0) {
                    switchHalf(
                        title: L10n.pause,
                        systemImage: "pause.fill",
                        selected: !isPaused
                    )
                    switchHalf(
                        title: L10n.resume,
                        systemImage: "play.fill",
                        selected: isPaused
                    )
                }
            }
        }
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .contentShape(Capsule())
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPaused ? L10n.resume : L10n.pause)
        .accessibilityAddTraits(.isButton)
    }

    private func switchHalf(title: String, systemImage: String, selected: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        NotificationsListView()
    }
    .modelContainer(PreviewData.shared.container)
    .environment(PreviewData.shared.recordingService)
}
