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
        .onGlassShell()
        .environment(\.shellPalette, settings.shellPalette)
        .toastHost()
        .deleteConfirmHost()
        .onAppear { AppIconSync.syncWindowStyle(settings.appearanceMode) }
        .onChange(of: settings.appearanceMode) { _, mode in
            AppIconSync.syncWindowStyle(mode)
        }
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
                .modifier(TrailhoundTabContentChrome())
                .tabItem {
                    Label(L10n.tabTrips, systemImage: "map")
                }
                .badge(isRecordingSession ? "" : nil)
                .tag(AppTab.trips)

                Group {
                    if tabSelection.selectedTab == .pairing {
                        PairingTabView()
                    } else {
                        AtmosphericBackground()
                    }
                }
                .modifier(TrailhoundTabContentChrome())
                .tabItem {
                    Label(L10n.string("vehicles.tab.title"), systemImage: "car")
                }
                .tag(AppTab.pairing)

                NavigationStack {
                    if tabSelection.selectedTab == .stats {
                        StatsView()
                    } else {
                        AtmosphericBackground()
                    }
                }
                .background(Color.clear)
                .modifier(TrailhoundTabContentChrome())
                .tabItem {
                    Label(L10n.tabStats, systemImage: "chart.bar")
                }
                .tag(AppTab.stats)

                NavigationStack {
                    if tabSelection.selectedTab == .settings {
                        SettingsView()
                    } else {
                        AtmosphericBackground()
                    }
                }
                .background(Color.clear)
                .modifier(TrailhoundTabContentChrome())
                .tabItem {
                    Label(L10n.tabSettings, systemImage: "gearshape")
                }
                .tag(AppTab.settings)
            }
            .background(Color.clear)
            .background(TrailhoundTabBarCompactInstaller())
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TrailhoundFloatingTabBar(
                    selection: $tabSelection.selectedTab,
                    isRecording: isRecordingSession
                )
            }
            .animation(TrailhoundMotion.tabSwitch, value: tabSelection.selectedTab)
        }
        .modifier(TrailhoundRootTint())
        .task {
            await authenticateOnLaunch()
            processPendingRecordingRequests()
            AppIconSync.apply(settings.shellPalette)
            // If a trip is already active when the main UI appears (e.g. launched
            // from the lock screen widget, or started while locked), land on trips.
            if tripRecordingService.state.isActiveSession {
                tabSelection.openTrips()
            }
        }
        .onChange(of: settings.shellPalette) { _, palette in
            AppIconSync.apply(palette)
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

private struct TrailhoundRootTint: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        if colorScheme == .light, GlassEngineResolver.lightAvoidsWhiteChromeTint {
            content
        } else {
            content.tint(shellPalette.shellTint(for: colorScheme))
        }
    }
}

/// Keep in-tab chrome (nav buttons, glass controls) on `shellTint`.
/// Light iOS 26 skips white tint so toolbar liquid is not a second white plate.
private struct TrailhoundTabContentChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        if colorScheme == .light, GlassEngineResolver.lightAvoidsWhiteChromeTint {
            content
        } else {
            content.tint(shellPalette.shellTint(for: colorScheme))
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
