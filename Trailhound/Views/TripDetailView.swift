import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

@MainActor
private enum TripDetailRevealSession {
    static var completedTripIDs: Set<UUID> = []

    static func markCompleted(_ tripID: UUID) {
        completedTripIDs.insert(tripID)
    }

    static func hasCompleted(_ tripID: UUID) -> Bool {
        completedTripIDs.contains(tripID)
    }
}

/// Resting overlay height — editing growth lives in `TripDetailEditPanel`.
private enum TripDetailPanelLayout {
    static let heightFraction: CGFloat = TripDetailKeyboardLayout.restHeightFraction
    static let editingHeightFraction: CGFloat = TripDetailKeyboardLayout.editingHeightFraction
}

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var modelContext
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.colorScheme) private var colorScheme
    @Query private var places: [SavedPlace]
    @Bindable private var settings = AppSettings.shared

    @State private var mapCameraBox = TripDetailMapCameraBox()
    /// Used so camera fit spans match the portrait map aspect.
    @State private var mapViewportSize: CGSize = CGSize(width: 390, height: 844)
    /// Status + transparent nav overlay height in points (not a fraction of a stale size).
    @State private var mapTopChromePoints: CGFloat = 96
    /// Tab bar + home-indicator band the map draws under (`.ignoresSafeArea(.bottom)`).
    @State private var mapBottomChromePoints: CGFloat = 83
    /// Last laid-out panel height — refit uses this, not only the layout fraction.
    @State private var lastLivePanelHeight: CGFloat = 0
    @State private var mapRefitTask: Task<Void, Never>?
    @State private var shareImage: UIImage?
    @State private var shareCaption: String?
    @State private var showShareSheet = false
    @State private var isRenderingShareCard = false
    /// In-place map expand — panel slides away on the same MapKit instance (no sheet).
    @State private var isMapExpanded = false
    /// True while expand/collapse animation runs — freezes glass over the live map.
    @State private var isMapExpandTransitioning = false
    /// Style picker fades in after the panel has largely cleared.
    @State private var showExpandedMapChrome = false
    @State private var mapExpandTransitionTask: Task<Void, Never>?
    /// `nil` until the user picks — then Light/Dark are forced, not system-following.
    @State private var mapStyleOverride: TripDetailMapStyle?
    /// Recorded GPS count — filled after the first paint so opening never faults points.
    @State private var recordedPointCount: Int = 0
    @State private var routeRevealProgress: Double = 0
    @State private var startPinVisible = false
    @State private var endPinVisible = false
    @State private var showAllStops = false
    @State private var didStartDetailReveal = false
    @State private var detailRevealTask: Task<Void, Never>?
    @State private var panelRisen = false
    /// 0 = muted settle veil, 1 = map clear. Held muted until the route path is ready.
    @State private var mapClarity: Double = 0
    @State private var showSharePreview = false
    @State private var pendingSystemShare = false
    @State private var statCountProgress: [String: Double] = [:]
    @State private var speedChartRevealProgress: Double = 0
    @State private var tripDetailViewModel: TripDetailViewModel?
    @State private var routeLoadTask: Task<Void, Never>?
    /// Bumped to ask `TripDetailEditPanel` to resign first responder.
    @State private var keyboardDismissSignal = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glassFrozen: Bool { isMapExpandTransitioning }

    private var panelVisible: Bool { panelRisen && !isMapExpanded }

    private var resolvedViewModel: TripDetailViewModel {
        if let tripDetailViewModel {
            return tripDetailViewModel
        }
        return TripDetailViewModel(
            trip: trip,
            places: places,
            privacyRadius: settings.privacyRadiusMeters,
            displayPieces: nil
        )
    }

    private var sortedStops: [TripStop] {
        trip.stops.sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()

            GeometryReader { geometry in
                let containerHeight = geometry.size.height
                let panelHeight = livePanelHeight(containerHeight: containerHeight)
                let mapPeek = mapTopChromePoints + 24
                // Expanded: keep the speed chips sitting on the tab bar, not under it.
                // GeometryReader is under `.ignoresSafeArea(.bottom)`, so inset 0 buries them.
                // Always rest height — editing growth is owned by TripDetailEditPanel.
                let chromeBottomInset = panelVisible ? panelHeight : mapBottomChromePoints
                ZStack(alignment: .bottom) {
                    // Full-screen map — never resized by the panel (Apple Maps pattern).
                    // Keep interactive from first paint so toggling modes does not rebuild MapKit.
                    tripDetailMapLayer(interactive: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture {
                            dismissEditKeyboard()
                        }

                    // Soft settle veil — fades out before the sheet rises (does not remount MapKit).
                    Color.black.opacity(0.42 * (1 - mapClarity))
                        .allowsHitTesting(false)
                        .animation(reduceMotion ? nil : TrailhoundMotion.mapClear, value: mapClarity)

                    // Cheap chrome sits above the map and tracks panel height without resizing MapKit.
                    ZStack(alignment: .topTrailing) {
                        if !networkMonitor.isConnected {
                            Text(L10n.tripMapOfflineHint)
                                .font(.caption2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .glassChrome(cornerRadius: 14, frozen: glassFrozen)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                .padding(12)
                                .opacity(mapClarity)
                        }

                        compactSpeedLegend
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(12)
                            .opacity(mapClarity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, chromeBottomInset)
                    .animation(
                        reduceMotion ? nil : (isMapExpanded
                            ? TrailhoundMotion.mapExpand
                            : TrailhoundMotion.mapCollapse),
                        value: isMapExpanded
                    )
                    .allowsHitTesting(false)

                    TripDetailEditPanel(
                        trip: trip,
                        viewModel: resolvedViewModel,
                        glassFrozen: glassFrozen,
                        panelRisen: panelRisen,
                        restHeight: panelHeight,
                        mapPeek: mapPeek,
                        reduceMotion: reduceMotion,
                        statCountProgress: statCountProgress,
                        speedChartRevealProgress: speedChartRevealProgress,
                        recordedPointCount: $recordedPointCount,
                        keyboardDismissSignal: $keyboardDismissSignal,
                        onDisplayRefresh: { refreshTripDetailViewModel() },
                        onRouteInvalidated: { reloadRouteAfterTrim() }
                    )
                        .frame(maxWidth: .infinity)
                        .background {
                            // Opaque wash — glass cards and the translucent tab bar never sample the map.
                            ZStack {
                                Color(.systemBackground)
                                AtmosphericBackground(style: .lightweight)
                            }
                        }
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 18,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 18,
                                style: .continuous
                            )
                        )
                        .offset(y: panelVisible ? 0 : panelHeight + 24)
                        .opacity(panelVisible ? 1 : 0)
                        .animation(reduceMotion ? nil : TrailhoundMotion.sheetRise, value: panelRisen)
                        .animation(
                            reduceMotion ? nil : (isMapExpanded
                                ? TrailhoundMotion.mapExpand
                                : TrailhoundMotion.mapCollapse),
                            value: isMapExpanded
                        )
                        .allowsHitTesting(panelVisible)
                }
                // Content-sized overlay — outside frozen chrome so the picker stays tappable.
                .overlay(alignment: .topTrailing) {
                    if showExpandedMapChrome {
                        expandedMapStylePicker
                            .padding(.top, 12)
                            .padding(.trailing, 12)
                            .transition(.opacity)
                    }
                }
                .onAppear {
                    refreshMapChromeInsets(from: geometry)
                    lastLivePanelHeight = panelHeight
                }
                .onChange(of: geometry.size) { _, newSize in
                    refreshMapChromeInsets(from: geometry)
                    if !isMapExpanded {
                        lastLivePanelHeight = livePanelHeight(containerHeight: newSize.height)
                    }
                    if panelRisen, didStartDetailReveal {
                        refitMapToVisibleGap(
                            panelHeight: isMapExpanded ? 0 : nil,
                            animated: false
                        )
                    }
                }
                .onChange(of: panelHeight) { _, newHeight in
                    guard !isMapExpanded else { return }
                    lastLivePanelHeight = newHeight
                }
            }
        }
        // Extend under the translucent tab bar so the card wash covers it — no map peeking through.
        .ignoresSafeArea(edges: .bottom)
        .glassNavigationChrome()
        .accessibilityIdentifier("tripDetail.screen")
        .navigationTitle(L10n.tripDetailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await renderShareCard() }
                } label: {
                    if isRenderingShareCard {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(isRenderingShareCard)
                .accessibilityLabel(L10n.share)

                Button {
                    toggleMapExpanded()
                } label: {
                    Image(
                        systemName: isMapExpanded
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right"
                    )
                }
                .accessibilityLabel(isMapExpanded ? L10n.mapExitFullscreen : L10n.mapFullscreen)
            }
        }
        .sheet(isPresented: $showSharePreview, onDismiss: {
            if pendingSystemShare {
                pendingSystemShare = false
                showShareSheet = true
            } else {
                shareImage = nil
                shareCaption = nil
            }
        }) {
            if let shareImage {
                TripSharePreviewSheet(
                    image: shareImage,
                    caption: shareCaption,
                    onShare: {
                        pendingSystemShare = true
                        showSharePreview = false
                    },
                    onClose: {
                        pendingSystemShare = false
                        showSharePreview = false
                    }
                )
            }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            shareImage = nil
            shareCaption = nil
            pendingSystemShare = false
        }) {
            if let shareImage {
                let items: [Any] = shareCaption.map { [shareImage, $0] } ?? [shareImage]
                ActivityShareSheet(items: items)
                    .ignoresSafeArea()
            }
        }
        .overlay {
            if isRenderingShareCard {
                ZStack {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                    VStack(spacing: 14) {
                        TrailhoundBrandMark(showsWordmark: true, symbolSize: 56)
                        ProgressView()
                            .controlSize(.large)
                        Text(L10n.shareCardPreparing)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(28)
                    .glassCard(cornerRadius: 16, contentInset: 0)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isRenderingShareCard)
        .onAppear {
            if tripDetailViewModel == nil {
                tripDetailViewModel = TripDetailViewModel(
                    trip: trip,
                    places: places,
                    privacyRadius: settings.privacyRadiusMeters,
                    displayPieces: nil
                )
            }

            // Keep legend muted until the path is ready — map itself stays visible (no black veil).
            mapClarity = 0
            panelRisen = false
            didStartDetailReveal = false
            showAllStops = false
            recordedPointCount = 0
            routeRevealProgress = 0
            startPinVisible = false
            endPinVisible = false

            // Frame endpoints immediately so MapKit never sits on .automatic (blank/world flash).
            if let region = fittedMapRegion(panelHeight: mapViewportSize.height * TripDetailPanelLayout.heightFraction) {
                applyFittedCamera(region: region, animated: false)
            }

            routeLoadTask?.cancel()
            routeLoadTask = Task { @MainActor in
                await loadDisplayPathAndReveal()
            }
        }
        .onDisappear {
            logTripDetailDiagnostics(context: "disappear")
            if routeRevealProgress >= 0.95 {
                TripDetailRevealSession.markCompleted(trip.id)
            }
            detailRevealTask?.cancel()
            detailRevealTask = nil
            routeLoadTask?.cancel()
            routeLoadTask = nil
            mapRefitTask?.cancel()
            mapRefitTask = nil
            mapExpandTransitionTask?.cancel()
            mapExpandTransitionTask = nil
            didStartDetailReveal = false
            showAllStops = false
            recordedPointCount = 0
            isMapExpanded = false
            isMapExpandTransitioning = false
            showExpandedMapChrome = false
            // The detail map is the only screen that needs every GPS point; holding them past
            // dismissal is how browsing a long library grows memory without bound.
            trip.invalidatePointCaches()
        }
    }

    private func loadDisplayPathAndReveal() async {
        let pieces = await TripRoutePathCache.shared.path(
            for: trip,
            container: modelContext.container
        )
        guard !Task.isCancelled else { return }

        tripDetailViewModel = TripDetailViewModel(
            trip: trip,
            places: places,
            privacyRadius: settings.privacyRadiusMeters,
            displayPieces: pieces
        )

        // Defer faulting recorded points until after the first paint + path are ready.
        await Task.yield()
        guard !Task.isCancelled else { return }
        recordedPointCount = trip.points.count

        let plan = TripDetailRevealPolicy.animationPlan(
            pointCount: resolvedViewModel.displayPointCount,
            reduceMotion: reduceMotion
        )

        if !plan.shouldAnimate || TripDetailRevealSession.hasCompleted(trip.id) {
            finishDetailRevealInstant()
            logTripDetailDiagnostics(context: "appear instant")
        } else {
            startDetailReveal(plan: plan)
            logTripDetailDiagnostics(context: "appear animate")
        }
    }

    private func startDetailReveal(plan: TripDetailRevealPolicy.AnimationPlan) {
        guard !didStartDetailReveal else { return }
        didStartDetailReveal = true

        routeRevealProgress = 0
        startPinVisible = false
        endPinVisible = false
        showAllStops = false
        mapClarity = 0
        panelRisen = false
        statCountProgress = Dictionary(
            uniqueKeysWithValues: resolvedViewModel.summaryMetrics.map { ($0.id, 0.0) }
        )
        speedChartRevealProgress = 0

        if let region = fittedMapRegion(panelHeight: mapViewportSize.height * TripDetailPanelLayout.heightFraction) {
            applyFittedCamera(region: region, animated: false)
        }

        detailRevealTask?.cancel()
        detailRevealTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }

            // Beat: map clear
            withAnimation(TrailhoundMotion.mapClear) {
                mapClarity = 1
            }

            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }

            // Beat: frosted sheet rise
            withAnimation(TrailhoundMotion.sheetRise) {
                panelRisen = true
            }

            scheduleMapRefit(panelHeight: mapViewportSize.height * TripDetailPanelLayout.heightFraction)

            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }

            // Beat: start pin → route draw → end pin
            withAnimation(TrailhoundMotion.pinPop) {
                startPinVisible = true
            }

            await runContentReveal(plan: plan)
        }
    }

    private func runContentReveal(plan: TripDetailRevealPolicy.AnimationPlan) async {
        let metrics = resolvedViewModel.summaryMetrics
        let ticks = max(plan.tickCount, 1)
        let stepSleep = Duration.milliseconds(plan.stepSleepMilliseconds)

        for tick in 1...ticks {
            try? await Task.sleep(for: stepSleep)
            guard !Task.isCancelled else { return }
            let raw = Self.smoothstep(Double(tick) / Double(ticks))
            let progress = TripDetailRevealPolicy.quantizedProgress(
                rawProgress: raw,
                tick: tick,
                tickCount: ticks
            )
            routeRevealProgress = progress
            for metric in metrics {
                statCountProgress[metric.id] = progress
            }
            speedChartRevealProgress = progress
        }

        routeRevealProgress = 1
        for metric in metrics {
            statCountProgress[metric.id] = 1
        }
        speedChartRevealProgress = 1
        showAllStops = true

        TripDetailRevealSession.markCompleted(trip.id)

        withAnimation(TrailhoundMotion.pinPop) {
            endPinVisible = true
        }
    }

    private static func smoothstep(_ t: Double) -> Double {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    private func finishDetailRevealInstant() {
        didStartDetailReveal = true
        detailRevealTask?.cancel()
        detailRevealTask = nil
        routeRevealProgress = 1
        startPinVisible = true
        endPinVisible = true
        showAllStops = true
        mapClarity = 1
        panelRisen = true
        statCountProgress = Dictionary(
            uniqueKeysWithValues: resolvedViewModel.summaryMetrics.map { ($0.id, 1.0) }
        )
        speedChartRevealProgress = 1
        TripDetailRevealSession.markCompleted(trip.id)
        // Full-screen map: frame the route into the gap above the live panel.
        scheduleMapRefit(
            panelHeight: mapViewportSize.height * TripDetailPanelLayout.heightFraction,
            animated: false,
            delayMilliseconds: 80
        )
    }

    private func setMapCamera(_ position: MapCameraPosition) {
        // Update binding only — remounting Map (e.g. via .id) blanks tiles and flashes black.
        mapCameraBox.position = position
    }

    private func livePanelHeight(containerHeight: CGFloat) -> CGFloat {
        containerHeight * TripDetailPanelLayout.heightFraction
    }

    /// `GeometryReader` under `.ignoresSafeArea(.bottom)` reports a zero bottom inset.
    /// Read the key window so the tab bar + home indicator are real points.
    private func refreshMapChromeInsets(from geometry: GeometryProxy) {
        mapViewportSize = geometry.size
        let window = windowSafeInsets
        let topSafe = max(geometry.safeAreaInsets.top, window.top, 54)
        mapTopChromePoints = topSafe + 44
        // 49 = standard UITabBar content height above the home indicator.
        mapBottomChromePoints = max(window.bottom, 34) + 49
    }

    private var windowSafeInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let inset = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets {
            return inset
        }
        return scenes.flatMap(\.windows).first?.safeAreaInsets
            ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    private func mapEdgePadding(panelHeight: CGFloat) -> UIEdgeInsets {
        let size = mapViewportSize
        if isMapExpanded {
            // Same chrome the user sees: nav + style picker above, tab bar + speed chips below.
            let stylePickerRow: CGFloat = 52
            let legendRow: CGFloat = 36
            let top = max(mapTopChromePoints, 96) + stylePickerRow
            let bottom = max(mapBottomChromePoints, 83) + legendRow
            let horizontal = max(size.width * 0.08, 24)
            return UIEdgeInsets(top: top, left: horizontal, bottom: bottom, right: horizontal)
        }
        let horizontal = max(size.width * 0.06, 16)
        // Legend sits just above the card; pins hang below their coordinates.
        let legendAndPins: CGFloat = 56
        let top = max(mapTopChromePoints, 96)
        let bottom = max(panelHeight, 0) + legendAndPins
        return UIEdgeInsets(top: top, left: horizontal, bottom: bottom, right: horizontal)
    }

    private func fittedMapRegion(panelHeight: CGFloat) -> MKCoordinateRegion? {
        let size = mapViewportSize
        guard size.width > 1, size.height > 1 else { return nil }
        return resolvedViewModel.mapRegion(
            mapSize: size,
            edgePadding: mapEdgePadding(panelHeight: panelHeight),
            margin: isMapExpanded ? 1.18 : 1.2
        )
    }

    private func applyFittedCamera(
        region: MKCoordinateRegion,
        animated: Bool,
        animation: Animation = TrailhoundMotion.gentle
    ) {
        // Use the fitted region directly. Converting to MapCamera + a fudged altitude
        // zooms in (~1.55× max-span) and clips the route off-center under the tab bar.
        let position = MapCameraPosition.region(region)
        if animated, !reduceMotion {
            withAnimation(animation) {
                setMapCamera(position)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                setMapCamera(position)
            }
        }
    }

    private func refitMapToVisibleGap(
        panelHeight: CGFloat? = nil,
        animated: Bool = true,
        animation: Animation = TrailhoundMotion.gentle
    ) {
        let size = mapViewportSize
        let height = panelHeight
            ?? (lastLivePanelHeight > 0
                ? lastLivePanelHeight
                : size.height * TripDetailPanelLayout.heightFraction)
        guard let region = fittedMapRegion(panelHeight: height) else { return }
        applyFittedCamera(region: region, animated: animated, animation: animation)
    }

    /// One camera settle after the sheet rises — avoid double-apply flash.
    private func scheduleMapRefit(
        panelHeight: CGFloat? = nil,
        animated: Bool = true,
        delayMilliseconds: UInt64 = 280
    ) {
        let height = panelHeight
            ?? (lastLivePanelHeight > 0
                ? lastLivePanelHeight
                : mapViewportSize.height * TripDetailPanelLayout.heightFraction)
        mapRefitTask?.cancel()
        mapRefitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }
            refitMapToVisibleGap(panelHeight: height, animated: animated)
        }
    }

    private func toggleMapExpanded() {
        let expanding = !isMapExpanded
        mapRefitTask?.cancel()
        mapExpandTransitionTask?.cancel()
        TrailhoundHaptics.selection()
        dismissEditKeyboard()

        let motion = expanding ? TrailhoundMotion.mapExpand : TrailhoundMotion.mapCollapse
        let durationMs: UInt64 = expanding ? 1400 : 1100
        let chromeFadeInMs: UInt64 = 750
        let restorePanelHeight = lastLivePanelHeight > 0
            ? lastLivePanelHeight
            : mapViewportSize.height * TripDetailPanelLayout.heightFraction

        if reduceMotion {
            isMapExpandTransitioning = false
            showExpandedMapChrome = expanding
            isMapExpanded = expanding
            refitMapToVisibleGap(
                panelHeight: expanding ? 0 : restorePanelHeight,
                animated: false
            )
            return
        }

        isMapExpandTransitioning = true
        if !expanding {
            withAnimation(TrailhoundMotion.gentle) {
                showExpandedMapChrome = false
            }
        }

        withAnimation(motion) {
            isMapExpanded = expanding
        }
        refitMapToVisibleGap(
            panelHeight: expanding ? 0 : restorePanelHeight,
            animated: true,
            animation: motion
        )

        mapExpandTransitionTask = Task { @MainActor in
            if expanding {
                try? await Task.sleep(for: .milliseconds(chromeFadeInMs))
                guard !Task.isCancelled else { return }
                withAnimation(TrailhoundMotion.gentle) {
                    showExpandedMapChrome = true
                }
                try? await Task.sleep(for: .milliseconds(durationMs - chromeFadeInMs))
            } else {
                try? await Task.sleep(for: .milliseconds(durationMs))
            }
            guard !Task.isCancelled else { return }
            isMapExpandTransitioning = false
        }
    }

    private var mapStyle: TripDetailMapStyle {
        mapStyleOverride ?? .matching(colorScheme)
    }

    private var expandedMapStylePicker: some View {
        Picker(L10n.mapStylePicker, selection: Binding(
            get: { mapStyle },
            set: { mapStyleOverride = $0 }
        )) {
            Text(L10n.mapStyleLight).tag(TripDetailMapStyle.standard)
            Text(L10n.mapStyleDark).tag(TripDetailMapStyle.dark)
        }
        .pickerStyle(.segmented)
        .glassSegmentedStyle()
        .frame(width: 180)
        .padding(8)
        .glassChrome(cornerRadius: 10, frozen: glassFrozen)
    }

    private var compactSpeedLegend: some View {
        HStack(spacing: 8) {
            legendChip(color: .green, text: L10n.speedLegendSlow)
            legendChip(color: .yellow, text: L10n.speedLegendMedium)
            legendChip(color: .red, text: L10n.speedLegendFast)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassChrome(cornerRadius: 14, frozen: glassFrozen)
    }

    private func legendChip(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2)
        }
    }

    private func mapStops(showAll: Bool) -> [TripDetailMapStop] {
        let vm = resolvedViewModel
        return sortedStops.map { stop in
            TripDetailMapStop(
                id: String(describing: stop.persistentModelID),
                coordinate: stop.coordinate,
                revealProgress: showAll ? 0 : vm.annotationRevealProgress(forStopAt: stop.coordinate)
            )
        }
    }

    @ViewBuilder
    private func tripDetailMapLayer(
        interactive: Bool,
        revealProgress: Double? = nil,
        forceShowAllStops: Bool = false
    ) -> some View {
        let progress = revealProgress ?? routeRevealProgress
        let settled = progress >= TripDetailRevealOverlays.settleProgress
        let showStops = forceShowAllStops || showAllStops || settled
        let stroke = TripDetailRevealOverlays.stroke(
            progress: progress,
            coloredSegments: settled
                ? resolvedViewModel.revealedSpeedColoredSegments(progress: progress)
                : [],
            fallbackCoordinates: resolvedViewModel.revealedFallbackCoordinates(progress: progress)
        )

        TripDetailMapLayer(
            style: mapStyle,
            interactive: interactive,
            routeRevealProgress: progress,
            drawCasing: stroke.drawCasing,
            revealedItems: stroke.revealedItems,
            revealedFallback: stroke.revealedFallback,
            startCoordinate: resolvedViewModel.routeStartCoordinate,
            endCoordinate: resolvedViewModel.routeEndCoordinate,
            startPinVisible: revealProgress == nil ? startPinVisible : true,
            endPinVisible: revealProgress == nil ? endPinVisible : true,
            showAllStops: showStops,
            stops: mapStops(showAll: showStops),
            reduceMotion: reduceMotion,
            cameraBox: mapCameraBox
        )
        .equatable()
    }

    private func renderShareCard() async {
        guard !isRenderingShareCard else { return }
        isRenderingShareCard = true
        defer { isRenderingShareCard = false }

        let privacyRadius = settings.privacyRadiusMeters
        guard let image = await TripShareCardRenderer.render(
            trip: trip,
            places: places,
            privacyRadius: privacyRadius
        ) else {
            AppErrorPresenter.shared.present(L10n.string("share.card.error"))
            return
        }
        shareImage = image
        shareCaption = TripShareCaption.build(
            trip: trip,
            places: places,
            privacyRadius: privacyRadius
        )
        showSharePreview = true
    }

    private func dismissEditKeyboard() {
        keyboardDismissSignal += 1
        KeyboardDismiss.dismiss()
    }

    private func refreshTripDetailViewModel() {
        tripDetailViewModel = TripDetailViewModel(
            trip: trip,
            places: places,
            privacyRadius: settings.privacyRadiusMeters,
            displayPieces: tripDetailViewModel?.displayPieces
        )
    }

    private func reloadRouteAfterTrim() {
        routeLoadTask?.cancel()
        routeLoadTask = Task { @MainActor in
            await loadDisplayPathAndReveal()
        }
    }

    private func logTripDetailDiagnostics(context: String) {
        let points = trip.sortedPoints
        let speedPointCount = points.filter { ($0.speedMps ?? 0) > 0 }.count
        let sampleCount = resolvedViewModel.speedSamples.count
        // colorSegs = speed-band polylines; routePieces = real gap splits from RouteDisplayPath.
        let colorSegCount = resolvedViewModel.speedColoredSegments.count
        let routePieceCount = resolvedViewModel.displayPieces?.count ?? 0
        let routeGapCount = max(0, routePieceCount - 1)

        DevLog.shared.log(
            .tripDetail,
            "\(context) trip=\(trip.id.uuidString.prefix(8)) points=\(points.count) displayPts=\(resolvedViewModel.displayPointCount) speedPts=\(speedPointCount) chartSamples=\(sampleCount) routePieces=\(routePieceCount) routeGaps=\(routeGapCount) colorSegs=\(colorSegCount) reveal=\(Int(routeRevealProgress * 100))% chartReveal=\(Int(speedChartRevealProgress * 100))%"
        )

        if points.count >= 2, sampleCount == 0 {
            DevLog.shared.warning(
                .tripDetail,
                "speed chart hidden (no speedMps>0 samples); map may show single-color route"
            )
        }
        if routeRevealProgress < 0.95, context.hasPrefix("disappear") {
            DevLog.shared.warning(
                .tripDetail,
                "left detail before reveal finished — next open may flash empty until instant reveal"
            )
        }
    }
}

private struct TripSharePreviewSheet: View {
    let image: UIImage
    let caption: String?
    let onShare: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground().ignoresSafeArea()

                VStack(spacing: 16) {
                    TrailhoundBrandMark(showsWordmark: true, symbolSize: 44)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
                        .padding(.horizontal, 20)

                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .lineLimit(4)
                    }

                    Button(action: onShare) {
                        Label(L10n.share, systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TrailhoundBrandColors.brandBottom)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
                .padding(.top, 8)
            }
            .navigationTitle(L10n.shareCardPreviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .glassNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.actionClose, action: onClose)
                }
            }
        }
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Speed chart route draw

struct SpeedChartRouteCanvas: View {
    let samples: [(id: Int, date: Date, speedKmh: Double)]
    let maxKmh: Double
    let progress: Double
    let tripStartedAt: Date
    let tripEndedAt: Date
    /// Typical spacing between plotted samples; the gap threshold scales off it.
    let sampleMedianIntervalSeconds: TimeInterval

    private var gapBreakSeconds: TimeInterval {
        SpeedChartSeries.gapBreakSeconds(medianIntervalSeconds: sampleMedianIntervalSeconds)
    }

    private var brandColor: Color { TrailhoundBrandColors.brandBottom }

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 2
            let baselineY = size.height - inset
            let revealed = SpeedChartSeries.revealedSamples(
                from: samples.map { ($0.date, $0.speedKmh) },
                progress: progress,
                gapBreakSeconds: gapBreakSeconds
            )
            let points = SpeedChartSeries.strokePoints(
                samples: revealed,
                gapBreakSeconds: gapBreakSeconds,
                project: { date, speedKmh in
                    projectedPoint(date: date, speedKmh: speedKmh, in: size, inset: inset)
                },
                baselineY: baselineY
            )
            guard !points.isEmpty else { return }

            if points.count == 1 {
                var dot = Path()
                dot.addEllipse(in: CGRect(x: points[0].x - 2, y: points[0].y - 2, width: 4, height: 4))
                context.fill(dot, with: .color(brandColor))
                return
            }

            var line = Path()
            line.move(to: points[0])
            for point in points.dropFirst() {
                line.addLine(to: point)
            }

            var area = Path()
            area.move(to: CGPoint(x: points[0].x, y: baselineY))
            area.addLine(to: points[0])
            for point in points.dropFirst() {
                area.addLine(to: point)
            }
            area.addLine(to: CGPoint(x: points[points.count - 1].x, y: baselineY))
            area.closeSubpath()

            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [brandColor.opacity(0.28), brandColor.opacity(0.04)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            context.stroke(
                line,
                with: .color(brandColor.opacity(0.35)),
                style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                line,
                with: .color(brandColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            if progress < 0.995, let tip = points.last {
                var glow = Path()
                glow.addEllipse(in: CGRect(x: tip.x - 4.5, y: tip.y - 4.5, width: 9, height: 9))
                context.fill(glow, with: .color(brandColor.opacity(0.28)))

                var tipDot = Path()
                tipDot.addEllipse(in: CGRect(x: tip.x - 2.5, y: tip.y - 2.5, width: 5, height: 5))
                context.fill(tipDot, with: .color(brandColor))
                context.stroke(tipDot, with: .color(.white.opacity(0.9)), lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }

    private func projectedPoint(date: Date, speedKmh: Double, in size: CGSize, inset: CGFloat) -> CGPoint {
        let dateSpan = max(tripEndedAt.timeIntervalSince(tripStartedAt), 1)
        let drawWidth = max(size.width - inset * 2, 1)
        let drawHeight = max(size.height - inset * 2, 1)
        let baselineY = size.height - inset
        let speedMax = max(maxKmh, 1)
        let xFraction = date.timeIntervalSince(tripStartedAt) / dateSpan
        let yFraction = min(1, max(0, speedKmh / speedMax))
        return CGPoint(
            x: inset + CGFloat(xFraction) * drawWidth,
            y: baselineY - CGFloat(yFraction) * drawHeight
        )
    }
}

#Preview {
    NavigationStack {
        TripDetailView(trip: PreviewData.sampleTrip)
    }
    .modelContainer(PreviewData.shared.container)
    .environment(NetworkMonitor.shared)
}
