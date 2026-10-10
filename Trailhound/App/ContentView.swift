import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(AppLockService.self) private var appLockService
    @Environment(TripRecordingService.self) private var tripRecordingService
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Bindable private var settings = AppSettings.shared
    @Bindable private var tabSelection = TabSelection.shared
    @State private var windowSize: CGSize = .zero
    @State private var windowSafeTop: CGFloat = 0
    @State private var windowSafeLeft: CGFloat = 0
    @State private var windowSafeRight: CGFloat = 0
    @State private var windowTrailingColumn: CGFloat = 0
    /// Distance from the content's trailing edge to the window edge. Zero when the root is full bleed.
    @State private var windowContentTrailingGap: CGFloat = 0
    @State private var windowContentLeadingGap: CGFloat = 0
    @State private var windowContentTop: CGFloat = 0
    @State private var sideTabMidX: CGFloat = 0
    @State private var sideTabWindowWidth: CGFloat = 0
    /// Window Y of the top tab glyph. Chrome stacks above this.
    @State private var sideTabFirstIconMinY: CGFloat = 0
    /// Overlay top-leading in window coordinates. Safe-area inset makes this non-zero.
    @State private var overlayOriginX: CGFloat = 0
    @State private var overlayOriginY: CGFloat = 0
    /// SwiftUI safe insets of the root. The wider one is the side-tab column.
    @State private var columnLeadingInset: CGFloat = 0
    @State private var columnTrailingInset: CGFloat = 0
    @State private var overlayWidth: CGFloat = 0

    var body: some View {
        Group {
            if !settings.hasCompletedOnboarding {
                OnboardingView()
            } else if settings.appLockEnabled && !appLockService.isUnlocked {
                AppLockView()
            } else {
                mainTabs
                    .animation(
                        TrailhoundMotion.layoutReflow(reduceMotion: reduceMotion),
                        value: layoutSnapshot.layoutClass
                    )
            }
        }
        .preferredColorScheme(settings.appearanceMode.preferredColorScheme)
        .onGlassShell()
        .toastHost()
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
                            publishWindowMetrics(geo)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                refreshSideColumn()
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                refreshSideColumn()
                            }
                        }
                        .onChange(of: geo.size) { _, _ in
                            sideTabMidX = 0
                            sideTabFirstIconMinY = 0
                            publishWindowMetrics(geo)
                        }
                        .onChange(of: geo.safeAreaInsets.trailing) { _, _ in
                            publishWindowMetrics(geo)
                        }
                        .onChange(of: geo.safeAreaInsets.leading) { _, _ in
                            publishWindowMetrics(geo)
                        }
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if showsSideColumnBell,
               settings.hasCompletedOnboarding,
               !(settings.appLockEnabled && !appLockService.isUnlocked),
               hasSideTabColumn {
                wideBookStatusActions
                    .offset(x: wideBookStatusX, y: wideBookStatusTop)
            }
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
        }
        .onAppear { syncWindowFill() }
        .onChange(of: settings.appearanceMode) { _, _ in syncWindowFill() }
        .onChange(of: settings.shellPalette) { _, _ in syncWindowFill() }
        .onChange(of: windowSize) { _, _ in syncWindowFill() }
    }

    private var isRecordingSession: Bool {
        tripRecordingService.state.isActiveSession
    }

    private var layoutSnapshot: TrailhoundLayoutSnapshot {
        let size = windowSize == .zero ? CGSize(width: 390, height: 844) : windowSize
        return TrailhoundLayoutResolver.snapshot(
            horizontal: horizontalSizeClass,
            vertical: verticalSizeClass,
            size: size,
            idiom: UIDevice.current.userInterfaceIdiom
        )
    }

    private func syncWindowFill() {
        AppIconSync.syncWindowStyle(settings.appearanceMode, palette: settings.shellPalette)
    }

    private func publishWindowMetrics(_ geo: GeometryProxy) {
        publishWindowSize(geo.size)
        let top = geo.safeAreaInsets.top
        if top != windowSafeTop { windowSafeTop = top }
        let column = TrailhoundSideTabGap.trailing(in: geo, layoutDirection: layoutDirection)
        if abs(column - windowTrailingColumn) > 1 { windowTrailingColumn = column }
        let gap = contentTrailingGap(in: geo)
        if abs(gap - windowContentTrailingGap) > 1 { windowContentTrailingGap = gap }
        let leadingGap = contentLeadingGap(in: geo)
        if abs(leadingGap - windowContentLeadingGap) > 1 { windowContentLeadingGap = leadingGap }
        let contentTop = geo.frame(in: .global).minY
        if contentTop > 0, abs(contentTop - windowContentTop) > 1 { windowContentTop = contentTop }
        let origin = geo.frame(in: .global)
        if abs(origin.minX - overlayOriginX) > 0.5 { overlayOriginX = origin.minX }
        if abs(origin.minY - overlayOriginY) > 0.5 { overlayOriginY = origin.minY }
        let wasLeading = sideColumnIsLeading
        if abs(geo.safeAreaInsets.leading - columnLeadingInset) > 0.5 {
            columnLeadingInset = geo.safeAreaInsets.leading
        }
        if abs(geo.safeAreaInsets.trailing - columnTrailingInset) > 0.5 {
            columnTrailingInset = geo.safeAreaInsets.trailing
        }
        if wasLeading != sideColumnIsLeading {
            sideTabMidX = 0
            sideTabFirstIconMinY = 0
        }
        if abs(geo.size.width - overlayWidth) > 0.5 { overlayWidth = geo.size.width }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        if let window {
            if abs(window.bounds.width - sideTabWindowWidth) > 1 {
                sideTabWindowWidth = window.bounds.width
            }
            if abs(window.safeAreaInsets.left - windowSafeLeft) > 1 {
                windowSafeLeft = window.safeAreaInsets.left
            }
            if abs(window.safeAreaInsets.right - windowSafeRight) > 1 {
                windowSafeRight = window.safeAreaInsets.right
            }
        }
        refreshSideColumn()
    }

    private func refreshSideColumn() {
        guard let side = sideTabColumn() else { return }
        if abs(side.midX - sideTabMidX) > 1 { sideTabMidX = side.midX }
        if abs(side.firstIconMinY - sideTabFirstIconMinY) > 1 {
            sideTabFirstIconMinY = side.firstIconMinY
        }
        let width = side.width
        if abs(width - windowTrailingColumn) > 1 { windowTrailingColumn = width }
    }

    private func contentLeadingGap(in geo: GeometryProxy) -> CGFloat {
        let frame = geo.frame(in: .global)
        guard frame.width > 1 else { return 0 }
        return frame.minX > 1 ? frame.minX : 0
    }

    private func sideTabColumn() -> (
        width: CGFloat,
        isLeading: Bool,
        top: CGFloat,
        midX: CGFloat,
        firstIconMinY: CGFloat
    )? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        guard let window else { return nil }
        return TrailhoundSideTabGap.sideColumn(in: window)
    }

    private func contentTrailingGap(in geo: GeometryProxy) -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        let frame = geo.frame(in: .global)
        guard let window, frame.width > 1 else { return 0 }
        let raw = layoutDirection == .rightToLeft
            ? frame.minX
            : window.bounds.width - frame.maxX
        return raw > 1 ? raw : 0
    }

    private func publishWindowSize(_ size: CGSize) {
        guard size != windowSize else { return }
        let previous = layoutSnapshot.layoutClass
        windowSize = size
        let next = layoutSnapshot.layoutClass
        guard previous != next else { return }
        let state = PerformanceSignposts.signposter.beginInterval("layout.reflow")
        PerformanceSignposts.signposter.endInterval("layout.reflow", state)
    }

    /// Side-column bell stays on every tab. Merge stays on Trips.
    private var showsSideColumnBell: Bool {
        hasSideTabColumn
    }

    private var showsWideBookMerge: Bool {
        tabSelection.selectedTab == .trips && tabSelection.wideBookTrailingVisible
    }

    /// Wider horizontal inset is the side-tab column. Window and SwiftUI insets both count.
    private var leadingColumnWidth: CGFloat {
        max(columnLeadingInset, windowSafeLeft)
    }

    private var trailingColumnWidth: CGFloat {
        max(columnTrailingInset, windowSafeRight)
    }

    /// Leading column when the left inset wins, trailing column when the right inset wins.
    private var sideColumnIsLeading: Bool {
        leadingColumnWidth > 20 && leadingColumnWidth >= trailingColumnWidth
    }

    private var hasSideTabColumn: Bool {
        sideColumnIsLeading
            || (trailingColumnWidth > 20 && overlayWidth > 1)
            || sideTabMidX > 20
    }

    /// Center of the tab column, in the overlay's coordinates.
    /// A stale glyph midX from the other rotation must not keep the buttons on the opposite edge.
    /// The circles sit a few points left of the tab glyphs; nudge them onto that center.
    private var wideBookStatusX: CGFloat {
        wideBookStatusXRaw + 6
    }

    private var wideBookStatusXRaw: CGFloat {
        let half: CGFloat = 22
        let glyphX = sideTabMidX - overlayOriginX
        if sideColumnIsLeading {
            if glyphX > 8, glyphX < leadingColumnWidth + 12 {
                return glyphX - half
            }
            return leadingColumnWidth / 2 - half - overlayOriginX
        }
        if trailingColumnWidth > 20, overlayWidth > 1 {
            let columnStart = overlayWidth - trailingColumnWidth
            if glyphX > columnStart - 12, glyphX < overlayWidth {
                return glyphX - half
            }
            return overlayWidth - trailingColumnWidth / 2 - half
        }
        if sideTabMidX > 20 {
            return glyphX - half
        }
        return 8
    }

    /// Bell and the button under it sit in the gap between the landscape camera
    /// and the first tab, centered on the tab glyphs.
    private var wideBookStatusTop: CGFloat {
        let cameraDrop: CGFloat = 24
        guard sideTabFirstIconMinY > 40 else { return max(windowSafeTop, 8) + cameraDrop }
        let raw = sideTabFirstIconMinY - 28 + cameraDrop - wideBookStatusStackHeight
        return raw - overlayOriginY
    }

    /// Positions the bell. The 14pt gap is the one the bell was tuned against;
    /// the live stack is tighter so only the merge button moves up.
    private var wideBookStatusStackHeight: CGFloat { 44 + 14 + 44 }

    private var wideBookStatusActions: some View {
        VStack(spacing: 4) {
            TrailhoundNotificationBell()
            if showsWideBookMerge {
                Button {
                    tabSelection.triggerWideBookTrailing()
                } label: {
                    GlassNavCircleIcon(systemName: tabSelection.wideBookTrailingSymbol)
                }
                .buttonStyle(.glassPlainHit)
                .accessibilityLabel(tabSelection.wideBookTrailingLabel)
            }
        }
        .background(WideBookStatusColumnMarker())
        .accessibilityIdentifier(TrailhoundSideTabGap.statusColumnMarker)
        .environment(\.shellPalette, settings.shellPalette)
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
                            .trailhoundShellToolbar(includesBell: !layoutSnapshot.placesChromeInSideColumn)
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
                            .trailhoundShellToolbar(includesBell: !layoutSnapshot.placesChromeInSideColumn)
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
                            .trailhoundShellToolbar(includesBell: !layoutSnapshot.placesChromeInSideColumn)
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

/// Marks the bell/merge stack so its glyphs are not measured as tab icons.
private struct WideBookStatusColumnMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> WideBookStatusColumnMarkerView {
        let view = WideBookStatusColumnMarkerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: WideBookStatusColumnMarkerView, context: Context) {
        uiView.tagHostIfCompact()
    }
}

private final class WideBookStatusColumnMarkerView: UIView {
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        tagHostIfCompact()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tagHostIfCompact()
    }

    func tagHostIfCompact() {
        guard let host = superview else { return }
        guard host.bounds.width < 180, host.bounds.height < 260, host.bounds.width > 1 else { return }
        host.accessibilityIdentifier = TrailhoundSideTabGap.statusColumnMarker
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
