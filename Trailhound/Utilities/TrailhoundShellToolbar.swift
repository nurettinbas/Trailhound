import SwiftData
import SwiftUI

/// Start (with the vehicle picker) and the notification bell on every tab root.
/// Start hides while a trip is already recording or paused.
struct TrailhoundShellToolbar: ViewModifier {
    var pageOwnsLeading: Bool = false

    @Environment(TripRecordingService.self) private var recordingService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \VehicleProfile.name) private var vehicles: [VehicleProfile]
    @Bindable private var tabSelection = TabSelection.shared
    @Bindable private var notificationStore = AppNotificationStore.shared

    func body(content: Content) -> some View {
        content.toolbar {
            if !pageOwnsLeading, showsStart {
                ToolbarItem(placement: .topBarLeading) {
                    startCluster
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                bellButton
            }
            .hideSharedToolbarBackgroundIfAvailable()
        }
    }

    private var showsStart: Bool {
        !recordingService.state.isActiveSession
    }

    private var startCluster: some View {
        HStack(spacing: 4) {
            if !vehicles.isEmpty {
                RecordingVehiclePicker(
                    vehicles: vehicles,
                    selectedVehicleID: recordingService.activeRecordingVehicleID(from: vehicles),
                    onSelect: { recordingService.setRecordingVehicle($0) }
                )
            }
            Button(action: startOrFocusRecording) {
                TrailhoundRunningHoundIcon(reduceMotion: reduceMotion)
            }
            .accessibilityLabel(L10n.string("action.start"))
            .accessibilityIdentifier("shell.start")
        }
    }

    private var bellButton: some View {
        Button {
            notificationStore.markAllRead()
            tabSelection.openNotifications()
        } label: {
            GlassToolbarSymbol(systemName: "bell")
        }
        .accessibilityLabel(L10n.notificationsTitle)
        .accessibilityValue(notificationStore.unreadCount > 0 ? "\(min(notificationStore.unreadCount, 99))" : "")
        .accessibilityIdentifier("trips.notifications")
        .overlay(alignment: .topTrailing) {
            if notificationStore.unreadCount > 0 {
                Text("\(min(notificationStore.unreadCount, 99))")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, notificationStore.unreadCount > 9 ? 5 : 0)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(GlassSemantic.notificationBadge, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                    }
                    .scaleEffect(0.7)
                    .padding(.top, 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private func startOrFocusRecording() {
        TrailhoundHaptics.selection()
        if recordingService.state.isActiveSession {
            tabSelection.focusRecordingCard()
            return
        }
        tabSelection.openTrips()
        if recordingService.startManualRecording() {
            tabSelection.focusRecordingCard()
        }
    }
}

extension View {
    func trailhoundShellToolbar(pageOwnsLeading: Bool = false) -> some View {
        modifier(TrailhoundShellToolbar(pageOwnsLeading: pageOwnsLeading))
    }
}
