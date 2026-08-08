import SwiftData
import SwiftUI
import UIKit

struct NotificationsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TripRecordingService.self) private var recordingService
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query private var vehicles: [VehicleProfile]
    @Bindable private var store = AppNotificationStore.shared
    @State private var roadVehiclePhoto: UIImage?

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

                    ForEach(visibleItems) { item in
                        notificationRow(item)
                            .background {
                                if !item.isRead {
                                    RoundedRectangle(cornerRadius: GlassTokens.cardRadius, style: .continuous)
                                        .fill(TrailhoundBrandColors.brandBottom.opacity(0.07))
                                }
                            }
                            .glassCard()
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
        .onAppear {
            store.reload()
        }
    }

    private var visibleItems: [StoredAppNotification] {
        store.items.filter { item in
            !isLiveTripSession(item, kind: store.kind(for: item))
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

    private var activeRecordingCard: some View {
        NotificationActiveRecordingCard(
            recordingService: recordingService,
            roadVehiclePhoto: roadVehiclePhoto,
            roadPhotoIdentity: roadPhotoIdentity,
            liveSessionBody: liveSessionBody,
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

    private func isLiveTripSession(_ item: StoredAppNotification, kind: AppNotificationKind) -> Bool {
        kind == .tripStarted
            && item.tripID == recordingService.activeTripID
            && recordingService.state.isActiveSession
    }

    @ViewBuilder
    private func notificationRow(_ item: StoredAppNotification) -> some View {
        let kind = store.kind(for: item)
        let trip = item.tripID.flatMap { tripID in trips.first(where: { $0.id == tripID }) }
        let showsOrphanActions = kind == .orphanStale
            && trip?.endedAt == nil
            && trip?.id != recordingService.activeTripID

        VStack(alignment: .leading, spacing: 8) {
            if let trip, !showsOrphanActions {
                NavigationLink {
                    TripDetailView(trip: trip)
                } label: {
                    rowContent(item: item, kind: kind)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    store.markRead(item.id)
                })
            } else {
                rowContent(item: item, kind: kind)
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

    private func rowContent(item: StoredAppNotification, kind: AppNotificationKind) -> some View {
        let isLiveSession = isLiveTripSession(item, kind: kind)

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: isLiveSession && recordingService.state == .paused ? "pause.circle.fill" : kind.systemImage)
                .font(.title3)
                .foregroundStyle(isLiveSession ? liveSessionTint : tint(for: kind))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayTitle(for: item, kind: kind, isLiveSession: isLiveSession))
                        .font(.subheadline.weight(item.isRead ? .regular : .semibold))
                    Spacer(minLength: 8)
                    Text(relativeDate(item.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(displayBody(for: item, kind: kind, isLiveSession: isLiveSession))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    private var liveSessionTint: Color {
        recordingService.state == .paused ? .orange : .green
    }

    private func displayTitle(
        for item: StoredAppNotification,
        kind: AppNotificationKind,
        isLiveSession: Bool
    ) -> String {
        guard isLiveSession else { return item.title }
        return recordingService.state == .paused ? L10n.recordingPaused : L10n.recordingStarted
    }

    private func displayBody(
        for item: StoredAppNotification,
        kind: AppNotificationKind,
        isLiveSession: Bool
    ) -> String {
        guard isLiveSession else { return item.body }
        return liveSessionBody
    }

    private func tint(for kind: AppNotificationKind) -> Color {
        switch kind {
        case .tripStarted: .green
        case .tripEnded: .blue
        case .tripDiscarded: .gray
        case .tripsMerged: .blue
        case .orphanStale: .orange
        case .recordingStopped: .red
        case .pairingSuggestion: .blue
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = DateFormatters.currentLocale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Isolated recording card — playback uses a sliding switch (not system bordered morph).
private struct NotificationActiveRecordingCard: View {
    let recordingService: TripRecordingService
    let roadVehiclePhoto: UIImage?
    let roadPhotoIdentity: String
    let liveSessionBody: String
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
            )
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
