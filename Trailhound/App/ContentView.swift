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
        .environment(\.glassEngineOverride, settings.glassEngineOverride)
        .environment(\.shellPalette, settings.shellPalette)
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
                .modifier(TrailhoundTabContentChrome())
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
                        AtmosphericBackground()
                    }
                }
                .modifier(TrailhoundTabContentChrome())
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
                        AtmosphericBackground()
                    }
                }
                .background(Color.clear)
                .modifier(TrailhoundTabContentChrome())
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
                        AtmosphericBackground()
                    }
                }
                .background(Color.clear)
                .modifier(TrailhoundTabContentChrome())
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
                            AtmosphericBackground()
                        }
                    }
                    .background(Color.clear)
                    .modifier(TrailhoundTabContentChrome())
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
            .background(TrailhoundTabBarCompactInstaller(selectedTab: tabSelection.selectedTab))
            .modifier(TrailhoundTabSelectionTint())
            .transaction { $0.animation = nil }
        }
        .modifier(TrailhoundTabBarChrome())
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

private struct TrailhoundTabBarChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
    }
}

private struct TrailhoundRootTint: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.tint(shellPalette.shellTint(for: colorScheme))
    }
}

/// iOS 26 selected-tab pill + icon follow the palette tint (not chrome `shellTint`).
private struct TrailhoundTabSelectionTint: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.tint(shellPalette.tintColor(for: colorScheme))
    }
}

/// Keep in-tab chrome (nav buttons, glass controls) on `shellTint`.
private struct TrailhoundTabContentChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.tint(shellPalette.shellTint(for: colorScheme))
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
