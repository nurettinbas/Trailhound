import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(AppLockService.self) private var appLockService
    @Environment(TripRecordingService.self) private var tripRecordingService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var settings = AppSettings.shared
    @Bindable private var tabSelection = TabSelection.shared
    @State private var windowSize: CGSize = .zero
    /// Layout the current turn started with. The live size is applied when the turn ends.
    @State private var presentedLayout = TrailhoundLayoutSnapshot.phone

    var body: some View {
        Group {
            if !settings.hasCompletedOnboarding {
                OnboardingView()
            } else if settings.appLockEnabled && !appLockService.isUnlocked {
                AppLockView()
            } else {
                mainTabs
                    .animation(layoutChangeAnimation, value: layoutSnapshot.layoutClass)
            }
        }
        .preferredColorScheme(settings.appearanceMode.preferredColorScheme)
        .onGlassShell()
        .toastHost(clearsTabBar: true)
        .deleteConfirmHost()
        .environment(\.shellPalette, settings.shellPalette)
        .environment(\.trailhoundLayout, layoutSnapshot)
        .coordinateSpace(name: TrailhoundWindowSpace.name)
        .background {
            ZStack {
                WindowRotationFill()
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            publishWindowSize(geo.size)
                        }
                        .onChange(of: geo.size) { _, newSize in
                            publishWindowSize(newSize)
                        }
                }
            }
            .allowsHitTesting(false)
        }
        .fullScreenCover(isPresented: $tabSelection.showNotificationsCover) {
            NavigationStack {
                NotificationsListView()
            }
            .glassNavigationChrome()
            .coordinateSpace(name: TrailhoundWindowSpace.name)
            .environment(\.trailhoundLayout, layoutSnapshot)
            .environment(\.shellPalette, settings.shellPalette)
            .preferredColorScheme(settings.appearanceMode.preferredColorScheme)
            .onGlassShell()
            .toastHost()
            .deleteConfirmHost()
        }
        .onAppear {
            syncWindowFill()
            rememberPresentedLayout()
        }
        .onChange(of: settings.appearanceMode) { _, _ in syncWindowFill() }
        .onChange(of: settings.shellPalette) { _, _ in syncWindowFill() }
        .onChange(of: windowSize) { _, _ in
            rememberPresentedLayout()
            guard !TrailhoundInterfaceRotation.shared.isRotating else { return }
            syncWindowFill()
        }
        .onChange(of: horizontalSizeClass) { _, _ in rememberPresentedLayout() }
        .onChange(of: verticalSizeClass) { _, _ in rememberPresentedLayout() }
        .onChange(of: TrailhoundInterfaceRotation.shared.isRotating) { _, rotating in
            guard !rotating else { return }
            rememberPresentedLayout()
            syncWindowFill()
        }
    }

    /// A turn already moves the window. A second spring fades the old page over the new one.
    private var layoutChangeAnimation: Animation? {
        let rotation = TrailhoundInterfaceRotation.shared
        if rotation.isRotating || rotation.suppressReflowAnimation { return nil }
        return TrailhoundMotion.layoutReflow(reduceMotion: reduceMotion)
    }

    private var isRecordingSession: Bool {
        tripRecordingService.state.isActiveSession
    }

    private var layoutSnapshot: TrailhoundLayoutSnapshot {
        TrailhoundLayoutResolver.snapshotDuringTurn(
            presented: presentedLayout,
            live: liveLayout,
            isRotating: TrailhoundInterfaceRotation.shared.isRotating
        )
    }

    private var liveLayout: TrailhoundLayoutSnapshot {
        let size = windowSize == .zero ? CGSize(width: 390, height: 844) : windowSize
        return TrailhoundLayoutResolver.snapshot(
            horizontal: horizontalSizeClass,
            vertical: verticalSizeClass,
            size: size,
            idiom: UIDevice.current.userInterfaceIdiom
        )
    }

    /// Keeps the snapshot a later turn will hold. Ignored while a turn is in progress
    /// so the live inner-display size cannot swap the hierarchy mid-rotation.
    private func rememberPresentedLayout() {
        guard !TrailhoundInterfaceRotation.shared.isRotating else { return }
        let next = liveLayout
        guard next != presentedLayout else { return }
        let classChanged = next.layoutClass != presentedLayout.layoutClass
        presentedLayout = next
        guard classChanged else { return }
        let state = PerformanceSignposts.signposter.beginInterval("layout.reflow")
        PerformanceSignposts.signposter.endInterval("layout.reflow", state)
    }

    private func syncWindowFill() {
        AppIconSync.syncWindowStyle(settings.appearanceMode, palette: settings.shellPalette)
    }

    private func publishWindowSize(_ size: CGSize) {
        guard size != windowSize else { return }
        // The new size can arrive before UIKit's turn. Rebuilding the page then
        // cancels the rotation and the Duo stays landscape, sideways in the hand.
        if TrailhoundLayoutResolver.aspectFlips(from: windowSize, to: size) {
            TrailhoundInterfaceRotation.shared.holdForIncomingTurn()
        }
        windowSize = size
    }

    private var mainTabs: some View {
        ZStack {
            AtmosphericBackground()

            TabView(selection: $tabSelection.selectedTab) {
                NavigationStack {
                    TripListView()
                }
                .background(Color.clear)
                .glassNavigationChrome()
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
                            .trailhoundShellToolbar()
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
                    if tabSelection.selectedTab == .year {
                        YearView()
                            .trailhoundShellToolbar()
                    } else {
                        AtmosphericBackground()
                    }
                }
                .background(Color.clear)
                .modifier(TrailhoundTabContentChrome())
                .tabItem {
                    TabBarItemLabel(
                        title: L10n.tabYear,
                        systemImage: "star",
                        selectedSystemImage: "star.fill",
                        isSelected: tabSelection.selectedTab == .year
                    )
                    .accessibilityIdentifier("tab.year")
                }
                .tag(AppTab.year)

                NavigationStack {
                    if tabSelection.selectedTab == .settings {
                        SettingsView()
                            .trailhoundShellToolbar()
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
            }
            .background(Color.clear)
            .background(TrailhoundTabBarCompactInstaller(selectedTab: tabSelection.selectedTab))
            .modifier(TrailhoundTabSelectionTint())
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
        if colorScheme == .light, GlassEngineResolver.lightAvoidsWhiteChromeTint {
            content
        } else {
            content.tint(shellPalette.shellTint(for: colorScheme))
        }
    }
}

/// Selected capsule uses the palette in Light and Dark. iOS 26 otherwise keeps
/// `AccentColor` (blue) on the side tab and the bottom tab.
private struct TrailhoundTabSelectionTint: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.tint(
            Color(
                uiColor: TrailhoundTabBarTheme.selectionTintUIColor(
                    palette: shellPalette,
                    scheme: colorScheme
                )
            )
        )
    }
}

/// Page chrome does not add a white Light tint — that plates the toolbar.
/// The tab bar tint stays on the `TabView`.
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

/// Tab bar forces `.fill` via `symbolVariants`. Pin exact outline/fill names.
/// Selected ink is the palette tint. Unselected stays the system tab color —
/// leaving it unset is what made the selected star `AccentColor` blue.
private struct TabBarItemLabel: View {
    let title: String
    let systemImage: String
    var selectedSystemImage: String? = nil
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        let selectedName = selectedSystemImage ?? "\(systemImage).fill"
        let icon = Image(systemName: isSelected ? selectedName : systemImage)
            .environment(\.symbolVariants, .none)
            .symbolRenderingMode(.monochrome)
        let label = Label {
            Text(title)
        } icon: {
            icon
        }
        if isSelected {
            label.foregroundStyle(shellPalette.tintColor(for: colorScheme))
        } else {
            label
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
