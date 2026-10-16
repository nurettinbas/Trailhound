import SwiftData
import SwiftUI

/// Start (with the vehicle picker) and the notification bell on every tab root.
/// Start hides while a trip is already recording or paused.
struct TrailhoundShellToolbar: ViewModifier {
    var pageOwnsLeading: Bool = false
    /// Split book and merge mode draw the bell inside their own trailing item.
    /// A second `.topBarTrailing` item is what iOS parks beside the side tab;
    /// rotating that circle drops the bell glyph.
    var pageOwnsTrailing: Bool = false

    @Environment(TripRecordingService.self) private var recordingService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \VehicleProfile.name) private var vehicles: [VehicleProfile]
    @Bindable private var tabSelection = TabSelection.shared

    func body(content: Content) -> some View {
        content.toolbar {
            if !pageOwnsLeading, showsStart {
                ToolbarItem(placement: .topBarLeading) {
                    startCluster
                }
            }
            if !pageOwnsTrailing {
                ToolbarItem(placement: .topBarTrailing) {
                    statusPair
                }
            }
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

    /// Bell and the Trips merge (or new-travel) button. Their own trailing capsule, horizontal, every orientation.
    private var statusPair: some View {
        GlassToolbarCluster(clustered: true) {
            TrailhoundNotificationBell()
            if showsTripsTrailing {
                Button {
                    tabSelection.triggerWideBookTrailing()
                } label: {
                    GlassToolbarSymbol(
                        systemName: tabSelection.wideBookTrailingSymbol,
                        pointSize: tabSelection.wideBookTrailingSymbol == "plus" ? nil : 15
                    )
                }
                .accessibilityLabel(tabSelection.wideBookTrailingLabel)
                .accessibilityIdentifier(tripsTrailingIdentifier)
            }
        }
    }

    private var showsTripsTrailing: Bool {
        tabSelection.selectedTab == .trips && tabSelection.wideBookTrailingVisible
    }

    private var tripsTrailingIdentifier: String {
        tabSelection.wideBookTrailingSymbol == "plus"
            ? SideColumnChromeID.newJournal
            : SideColumnChromeID.merge
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
    func trailhoundShellToolbar(pageOwnsLeading: Bool = false, pageOwnsTrailing: Bool = false) -> some View {
        modifier(TrailhoundShellToolbar(pageOwnsLeading: pageOwnsLeading, pageOwnsTrailing: pageOwnsTrailing))
    }
}

/// Liquid Glass bell in the trailing toolbar capsule, beside merge.
struct TrailhoundNotificationBell: View {
    @Bindable private var tabSelection = TabSelection.shared
    @Bindable private var notificationStore = AppNotificationStore.shared

    var body: some View {
        Button {
            notificationStore.markAllRead()
            tabSelection.openNotifications()
        } label: {
            GlassToolbarSymbol(systemName: "bell")
        }
        .accessibilityLabel(L10n.notificationsTitle)
        .accessibilityValue(notificationStore.unreadCount > 0 ? "\(min(notificationStore.unreadCount, 99))" : "")
        .accessibilityIdentifier(SideColumnChromeID.notifications)
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
}
