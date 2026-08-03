import SwiftData
import SwiftUI

struct NotificationsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TripRecordingService.self) private var recordingService
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Bindable private var store = AppNotificationStore.shared

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

    private var activeRecordingCard: some View {
        let isPaused = recordingService.state == .paused

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

            RecordingCarAnimationView(compact: true, isAnimating: !isPaused)
                .id(isPaused)

            Text(liveSessionBody)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .monospacedDigit()

            HStack(spacing: 10) {
                if isPaused {
                    Button {
                        recordingService.resumeRecording()
                    } label: {
                        Label(L10n.resume, systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button(role: .destructive) {
                        recordingService.stopManualRecording()
                    } label: {
                        Label(L10n.stop, systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        recordingService.pauseRecording()
                    } label: {
                        Label(L10n.pause, systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button(role: .destructive) {
                        recordingService.stopManualRecording()
                    } label: {
                        Label(L10n.stop, systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding(14)
        .background {
            RecordingCardStyle.glassSurface(isPaused: isPaused)
        }
        .animation(.easeInOut(duration: 0.25), value: isPaused)
        .clipShape(RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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

#Preview {
    NavigationStack {
        NotificationsListView()
    }
    .modelContainer(PreviewData.shared.container)
    .environment(PreviewData.shared.recordingService)
}
