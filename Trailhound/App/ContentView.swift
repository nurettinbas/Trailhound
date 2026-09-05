import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppLockService.self) private var appLockService
    @Environment(TripRecordingService.self) private var tripRecordingService
    @Bindable private var settings = AppSettings.shared
    @Bindable private var tabSelection = TabSelection.shared

    var body: some View {
        Group {
            if !settings.hasCompletedOnboarding {
                OnboardingView()
            } else if settings.appLockEnabled && !appLockService.isUnlocked {
                AppLockView()
            } else {
                mainTabs
            }
        }
        .preferredColorScheme(settings.appearanceMode.preferredColorScheme)
        .toastHost()
        .deleteConfirmHost()
    }

    private var isRecordingSession: Bool {
        
        tripRecordingService.state.isActiveSession
    }

    private var mainTabs: some View {
        ZStack {
            AtmosphericBackground()

            TabView(selection: $tabSelection.selectedTab) {
                NavigationStack {
                    TripListView()
                }
                .background(Color.clear)
                .tabItem {
                    TabBarItemLabel(
                        title: L10n.tabTrips,
                        systemImage: "map",
                        isSelected: tabSelection.selectedTab == .trips
                    )
                    .accessibilityIdentifier("tab.trips")
                }
                .badge(isRecordingSession ? "" : nil)
                .tag(AppTab.trips)

                Group {
                    if tabSelection.selectedTab == .pairing {
                        PairingTabView()
                    } else {
                        Color.clear
                    }
                }
                .tabItem {
                    TabBarItemLabel(
                        title: L10n.string("vehicles.tab.title"),
                        systemImage: "car",
                        isSelected: tabSelection.selectedTab == .pairing
                    )
                    .accessibilityIdentifier("tab.pairing")
                }
                .tag(AppTab.pairing)

                NavigationStack {
                    if tabSelection.selectedTab == .stats {
                        StatsView()
                    } else {
                        Color.clear
                    }
                }
                .background(Color.clear)
                .tabItem {
                    TabBarItemLabel(
                        title: L10n.tabStats,
                        systemImage: "chart.bar",
                        isSelected: tabSelection.selectedTab == .stats
                    )
                    .accessibilityIdentifier("tab.stats")
                }
                .tag(AppTab.stats)

                NavigationStack {
                    if tabSelection.selectedTab == .settings {
                        SettingsView()
                    } else {
                        Color.clear
                    }
                }
                .background(Color.clear)
                .tabItem {
                    TabBarItemLabel(
                        title: L10n.tabSettings,
                        systemImage: "gearshape",
                        isSelected: tabSelection.selectedTab == .settings
                    )
                    .accessibilityIdentifier("tab.settings")
                }
                .tag(AppTab.settings)

                if !UITestSupport.isEnabled {
                    NavigationStack {
                        if tabSelection.selectedTab == .devLog {
                            DevLogView()
                        } else {
                            Color.clear
                        }
                    }
                    .background(Color.clear)
                    .tabItem {
                        TabBarItemLabel(
                            title: L10n.string("Dev Log"),
                            systemImage: "ladybug",
                            isSelected: tabSelection.selectedTab == .devLog
                        )
                    }
                    .tag(AppTab.devLog)
                }
            }
            .background(Color.clear)
            .animation(TrailhoundMotion.tabSwitch, value: tabSelection.selectedTab)
        }
        .tint(TrailhoundBrandColors.brandBottom)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            await authenticateOnLaunch()
            processPendingRecordingRequests()
            // If a trip is already active when the main UI appears (e.g. launched
            // from the lock screen widget, or started while locked), land on trips.
            if tripRecordingService.state.isActiveSession {
                tabSelection.openTrips()
            }
        }
        .onChange(of: appLockService.isUnlocked) { _, isUnlocked in
            if isUnlocked {
                processPendingRecordingRequests()
            }
        }
        .onChange(of: tripRecordingService.state.isActiveSession) { wasActive, isActive in
            // A trip can start outside the app (lock screen widget, App Intent,
            // vehicle auto-connect). When it becomes active, surface the trips tab
            // so the user lands on the active trip regardless of the previous tab.
            if !wasActive && isActive {
                tabSelection.openTrips()
            }
        }
        .alert(L10n.externalStartConfirmTitle, isPresented: externalStartConfirmationBinding) {
            Button(L10n.externalStartConfirmAction) {
                tripRecordingService.confirmExternalStartRecording()
            }
            Button(L10n.cancel, role: .cancel) {
                tripRecordingService.cancelExternalStartRecording()
            }
        } message: {
            Text(L10n.externalStartConfirmMessage)
        }
        .appErrorAlert()
    }

    @MainActor
    private func authenticateOnLaunch() async {
        _ = await appLockService.authenticateIfNeeded(enabled: settings.appLockEnabled)
    }

    private func processPendingRecordingRequests() {
        RecordingControlBridge.refreshSharedDefaultsFromDisk()
        settings.expireStaleRecordingRequests()
        if settings.pendingStopRecordingRequest {
            tripRecordingService.processExternalStopRequest()
            return
        }
        if settings.pendingStartRecordingRequest || settings.awaitingExternalStartConfirmation {
            tripRecordingService.processExternalStartRequest()
            return
        }
        if settings.pendingPauseRecordingRequest {
            tripRecordingService.processExternalPauseRequest()
            return
        }
        if settings.pendingResumeRecordingRequest {
            tripRecordingService.processExternalResumeRequest()
        }
    }

    private var externalStartConfirmationBinding: Binding<Bool> {
        Binding(
            get: { settings.awaitingExternalStartConfirmation },
            set: { newValue in
                if !newValue, settings.awaitingExternalStartConfirmation {
                    tripRecordingService.cancelExternalStartRecording()
                }
            }
        )
    }

}

/// Tab bar forces `.fill` via `symbolVariants`. Pin exact outline/fill names and clear the env.
private struct TabBarItemLabel: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: isSelected ? "\(systemImage).fill" : systemImage)
                .environment(\.symbolVariants, .none)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.shared.container)
        .environment(PreviewData.shared.recordingService)
        .environment(LocationService())
        .environment(AppLockService())
        .environment(GeocodingRetryService(geocodingService: GeocodingService()))
        .environment(NetworkMonitor.shared)
}
