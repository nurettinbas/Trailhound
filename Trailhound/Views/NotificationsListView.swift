import SwiftData
import SwiftUI
import UIKit

struct NotificationsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TripRecordingService.self) private var recordingService
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query private var vehicles: [VehicleProfile]
    @Query private var schedules: [VehicleSchedule]
    @Bindable private var store = AppNotificationStore.shared
    @State private var roadVehiclePhoto: UIImage?
    @State private var openedTripID: UUID?

    var body: some View {
        Group {
            if store.items.isEmpty && !recordingService.state.isActiveSession {
                ContentUnavailableView(
                    L10n.notificationsEmptyTitle,
                    systemImage: "bell.slash",
                    description: Text(L10n.notificationsEmptyMessage)
                )
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
                            .glassCard(contentInset: 8)
                            // Unread tint on the full card — never as an inner content background
                            // (that created a smaller second layer inside the glass).
                            .overlay {
                                if !item.isRead {
                                    RoundedRectangle(cornerRadius: GlassTokens.cardRadius, style: .continuous)
                                        .fill(TrailhoundBrandColors.brandBottom.opacity(0.10))
                                        .allowsHitTesting(false)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.delete(item.id)
                                } label: {
                                    Label(L10n.delete, systemImage: "trash")
                                }
                                .destructiveTint()
                            }
                    }
                }
                .listStyle(.plain)
                .glassListChrome()
            }
        }
        .navigationTitle(L10n.notificationsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L10n.notificationsClearAll, role: .destructive) {
                        store.clearAll()
                    }
                    .disabled(store.items.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { openedTripID != nil },
            set: { if !$0 { openedTripID = nil } }
        )) {
            if let openedTripID,
               let trip = trips.first(where: { $0.id == openedTripID }) {
                TripDetailView(trip: trip)
            }
        }
        .onAppear {
            store.reload()
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
        // Open any finished trip (started/ended rows). Active/unfinished trips stay non-tappable.
        let canOpenTrip = trip?.endedAt != nil && !showsOrphanActions

        VStack(alignment: .leading, spacing: 6) {
            if canOpenTrip, let trip {
                rowContent(item: item, kind: kind, showsChevron: true)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.markRead(item.id)
                        openedTripID = trip.id
                    }
            } else {
                rowContent(item: item, kind: kind, showsChevron: false)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.markRead(item.id)
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
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        if TripRecoveryService.deleteOrphan(trip, in: modelContext) {
                            store.delete(item.id)
                            store.reload()
                            ToastPresenter.shared.show(.deleted)
                        }
                    } label: {
                        Label(L10n.delete, systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .destructiveTint()
                }
                .padding(.leading, 40)
            }
        }
    }

    private func rowContent(
        item: StoredAppNotification,
        kind: AppNotificationKind,
        showsChevron: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: kind.systemImage)
                .font(.body)
                .foregroundStyle(tint(for: kind, body: item.body))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(item.isRead ? .regular : .semibold))

                Text(item.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(relativeDate(item.createdAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
                // Vertically centered against the full row (title + body), not the title line.
                .accessibilityLabel(relativeDate(item.createdAt))

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
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
                    .foregroundStyle(isPaused ? .yellow : .red)
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
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .padding(14)
        .background {
            RecordingCardStyle.listSurface(isPaused: isPaused)
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

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 3
            let thumbWidth = (geo.size.width - inset * 2) / 2

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))

                Capsule(style: .continuous)
                    .fill(Color.white)
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
        .foregroundStyle(selected ? Color.black.opacity(0.88) : Color.white.opacity(0.88))
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
