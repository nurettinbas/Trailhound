import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

private struct FavoritePlaceSheetItem: Identifiable {
    enum Endpoint {
        case start
        case end
    }

    enum Mode {
        case create(PlaceDraft)
        case edit(UUID)
    }

    let mode: Mode
    let endpoint: Endpoint

    var id: String {
        switch mode {
        case .create(let draft):
            return "create-\(endpoint)-\(draft.id.uuidString)"
        case .edit(let placeID):
            return "edit-\(endpoint)-\(placeID.uuidString)"
        }
    }
}

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

/// Bottom panel snap points — grabber drag switches between more map / balanced / more details.
private enum TripDetailPanelDetent: CaseIterable, Equatable {
    case mapFocused
    case balanced
    case details

    var fraction: CGFloat {
        switch self {
        case .mapFocused: 0.28
        case .balanced: 0.52
        case .details: 0.78
        }
    }

    var lower: TripDetailPanelDetent? {
        switch self {
        case .mapFocused: nil
        case .balanced: .mapFocused
        case .details: .balanced
        }
    }

    var higher: TripDetailPanelDetent? {
        switch self {
        case .mapFocused: .balanced
        case .balanced: .details
        case .details: nil
        }
    }

    static func nearest(height: CGFloat, containerHeight: CGFloat) -> TripDetailPanelDetent {
        guard containerHeight > 0 else { return .balanced }
        let fraction = height / containerHeight
        return allCases.min(by: { abs($0.fraction - fraction) < abs($1.fraction - fraction) }) ?? .balanced
    }
}

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var modelContext
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Query private var places: [SavedPlace]
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Query private var vehicles: [VehicleProfile]
    @Bindable private var settings = AppSettings.shared

    @State private var mapCameraBox = TripDetailMapCameraBox()
    /// Used so camera fit spans match the portrait map aspect.
    @State private var mapViewportSize: CGSize = CGSize(width: 390, height: 844)
    /// Status + transparent nav overlay height in points (not a fraction of a stale size).
    @State private var mapTopChromePoints: CGFloat = 96
    /// Tab bar + home-indicator band the map draws under (`.ignoresSafeArea(.bottom)`).
    @State private var mapBottomChromePoints: CGFloat = 83
    /// Last laid-out panel height — refit uses this, not only detent.fraction.
    @State private var lastLivePanelHeight: CGFloat = 0
    @State private var mapRefitTask: Task<Void, Never>?
    @State private var noteText: String = ""
    @State private var selectedLabel: String = ""
    @State private var selectedCategoryID: String = BuiltInCategory.personalID.uuidString
    @State private var selectedVehicleID: UUID?
    @State private var startAddressText: String = ""
    @State private var endAddressText: String = ""
    @State private var startPlaceNameText: String = ""
    @State private var endPlaceNameText: String = ""
    @State private var shareImage: UIImage?
    @State private var shareCaption: String?
    @State private var showShareSheet = false
    @State private var isRenderingShareCard = false
    @FocusState private var noteFocused: Bool
    @State private var originalNoteText: String = ""
    /// In-place map expand — panel slides away on the same MapKit instance (no sheet).
    @State private var isMapExpanded = false
    /// True while expand/collapse animation runs — freezes glass over the live map.
    @State private var isMapExpandTransitioning = false
    /// Style picker fades in after the panel has largely cleared.
    @State private var showExpandedMapChrome = false
    @State private var mapExpandTransitionTask: Task<Void, Never>?
    @State private var mapStyle: TripDetailMapStyle = .standard
    @State private var editedStartedAt: Date = Date()
    @State private var editedEndedAt: Date = Date()
    @State private var trimHeadCount: Int = 0
    @State private var trimTailCount: Int = 0
    /// Recorded GPS count — filled after the first paint so opening never faults points.
    @State private var recordedPointCount: Int = 0
    @State private var routeRevealProgress: Double = 0
    @State private var startPinVisible = false
    @State private var endPinVisible = false
    @State private var showAllStops = false
    @State private var didStartDetailReveal = false
    @State private var detailRevealTask: Task<Void, Never>?
    @State private var panelRisen = false
    /// Bottom panel height detent — drag the grabber to resize map vs details.
    @State private var panelDetent: TripDetailPanelDetent = .balanced
    @State private var panelDragTranslation: CGFloat = 0
    /// 0 = muted settle veil, 1 = map clear. Held muted until the route path is ready.
    @State private var mapClarity: Double = 0
    @State private var showSharePreview = false
    @State private var pendingSystemShare = false
    @State private var statCountProgress: [String: Double] = [:]
    @State private var speedChartRevealProgress: Double = 0
    @State private var tripDetailViewModel: TripDetailViewModel?
    @State private var favoritePlaceSheet: FavoritePlaceSheetItem?
    @State private var routeLoadTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var glassFrozen: Bool { panelDragTranslation != 0 || isMapExpandTransitioning }

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

    private var sortedDetailVehicles: [VehicleProfile] {
        vehicles.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var vehiclePhotoPrefetchID: String {
        VehiclePhotoStore.prefetchTaskID(for: sortedDetailVehicles)
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()

            GeometryReader { geometry in
                let containerHeight = geometry.size.height
                let panelHeight = livePanelHeight(containerHeight: containerHeight)
                // Expanded: keep the speed chips sitting on the tab bar, not under it.
                // GeometryReader is under `.ignoresSafeArea(.bottom)`, so inset 0 buries them.
                let chromeBottomInset = panelVisible ? panelHeight : mapBottomChromePoints
                ZStack(alignment: .bottom) {
                    // Full-screen map — never resized by the panel (Apple Maps pattern).
                    // Keep interactive from first paint so toggling modes does not rebuild MapKit.
                    tripDetailMapLayer(interactive: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onTapGesture {
                            dismissNoteKeyboard()
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

                    detailPanel(containerHeight: containerHeight)
                        .frame(height: panelHeight)
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
                        .animation(reduceMotion ? nil : TrailhoundMotion.sheetRise, value: panelDetent)
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
        .dismissKeyboardOnTap(focus: $noteFocused)
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
        .sheet(item: $favoritePlaceSheet) { item in
            NavigationStack {
                favoritePlacePicker(for: item)
            }
        }
        .onAppear {
            noteText = trip.note ?? ""
            originalNoteText = noteText
            selectedLabel = trip.label ?? ""
            selectedCategoryID = trip.categoryID
            selectedVehicleID = trip.vehicleID
            startAddressText = trip.startAddress ?? ""
            endAddressText = trip.endAddress ?? ""
            startPlaceNameText = trip.startPlaceName ?? ""
            endPlaceNameText = trip.endPlaceName ?? ""
            editedStartedAt = trip.startedAt
            editedEndedAt = trip.endedAt ?? Date()

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
            if let region = fittedMapRegion(panelHeight: mapViewportSize.height * panelDetent.fraction) {
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

        if let region = fittedMapRegion(panelHeight: mapViewportSize.height * panelDetent.fraction) {
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

            scheduleMapRefit(panelHeight: mapViewportSize.height * panelDetent.fraction)

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
        // Full-screen map: frame the route into the gap above the live panel detent.
        scheduleMapRefit(
            panelHeight: mapViewportSize.height * panelDetent.fraction,
            animated: false,
            delayMilliseconds: 80
        )
    }

    private func setMapCamera(_ position: MapCameraPosition) {
        // Update binding only — remounting Map (e.g. via .id) blanks tiles and flashes black.
        mapCameraBox.position = position
    }

    private func livePanelHeight(containerHeight: CGFloat) -> CGFloat {
        let minHeight = containerHeight * TripDetailPanelDetent.mapFocused.fraction
        let maxHeight = containerHeight * TripDetailPanelDetent.details.fraction
        let base = containerHeight * panelDetent.fraction
        // Drag down → smaller panel (more map); drag up → taller panel.
        return min(maxHeight, max(minHeight, base - panelDragTranslation))
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
                : size.height * panelDetent.fraction)
        guard let region = fittedMapRegion(panelHeight: height) else { return }
        applyFittedCamera(region: region, animated: animated, animation: animation)
    }

    /// One camera settle after sheet/detent motion — avoid double-apply flash.
    private func scheduleMapRefit(
        panelHeight: CGFloat? = nil,
        animated: Bool = true,
        delayMilliseconds: UInt64 = 280
    ) {
        let height = panelHeight
            ?? (lastLivePanelHeight > 0
                ? lastLivePanelHeight
                : mapViewportSize.height * panelDetent.fraction)
        mapRefitTask?.cancel()
        mapRefitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }
            refitMapToVisibleGap(panelHeight: height, animated: animated)
        }
    }

    private func snapPanelDetent(containerHeight: CGFloat, velocityY: CGFloat) {
        guard !isMapExpanded else { return }
        let live = livePanelHeight(containerHeight: containerHeight)
        var target = TripDetailPanelDetent.nearest(height: live, containerHeight: containerHeight)
        // Fling: downward velocity favors more map; upward favors more details.
        if velocityY > 900 {
            target = target.lower ?? target
        } else if velocityY < -900 {
            target = target.higher ?? target
        }
        let targetHeight = containerHeight * target.fraction
        withAnimation(reduceMotion ? nil : TrailhoundMotion.sheetRise) {
            panelDetent = target
            panelDragTranslation = 0
        }
        lastLivePanelHeight = targetHeight
        scheduleMapRefit(panelHeight: targetHeight)
    }

    private func toggleMapExpanded() {
        let expanding = !isMapExpanded
        mapRefitTask?.cancel()
        mapExpandTransitionTask?.cancel()
        TrailhoundHaptics.selection()
        dismissNoteKeyboard()

        let motion = expanding ? TrailhoundMotion.mapExpand : TrailhoundMotion.mapCollapse
        let durationMs: UInt64 = expanding ? 1400 : 1100
        let chromeFadeInMs: UInt64 = 750
        let restorePanelHeight = lastLivePanelHeight > 0
            ? lastLivePanelHeight
            : mapViewportSize.height * panelDetent.fraction

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

    private var expandedMapStylePicker: some View {
        Picker(L10n.mapStylePicker, selection: $mapStyle) {
            Text(L10n.mapStyleLight).tag(TripDetailMapStyle.standard)
            Text(L10n.mapStyleDark).tag(TripDetailMapStyle.dark)
        }
        .pickerStyle(.segmented)
        .glassSegmentedStyle()
        .frame(width: 180)
        .padding(8)
        .glassChrome(cornerRadius: 10, frozen: glassFrozen)
    }

    private func refitMapForPanelDetent(_ detent: TripDetailPanelDetent, animated: Bool = true) {
        let height = mapViewportSize.height * detent.fraction
        lastLivePanelHeight = height
        if animated {
            scheduleMapRefit(panelHeight: height, animated: true)
        } else {
            refitMapToVisibleGap(panelHeight: height, animated: false)
        }
    }

    @ViewBuilder
    private func detailPanel(containerHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            panelGrabber(containerHeight: containerHeight)

            if panelRisen {
                ScrollView(.vertical, showsIndicators: true) {
                    detailPanelContent
                }
                .scrollBounceBehavior(.basedOnSize)
                .dismissKeyboardOnScroll()
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var detailPanelContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            tripHeader

            statsStrip

            if !resolvedViewModel.speedSamples.isEmpty {
                speedChartCard
            }

            if !sortedStops.isEmpty {
                detailSection(title: L10n.tripStopsSection) {
                    ForEach(Array(sortedStops.enumerated()), id: \.element.persistentModelID) { index, stop in
                        TripStopEditRow(stop: stop)
                        if index < sortedStops.count - 1 {
                            Divider()
                        }
                    }
                }
            }

            if trip.endedAt != nil {
                detailSplitSection(title: L10n.tripEditTimesSection) {
                    tripTimePicker(
                        title: L10n.tripStartedAt,
                        selection: $editedStartedAt
                    )
                } right: {
                    tripTimePicker(
                        title: L10n.tripEndedAt,
                        selection: $editedEndedAt
                    )
                }
            } else {
                detailSection(title: L10n.tripEditTimesSection) {
                    tripTimePicker(
                        title: L10n.tripStartedAt,
                        selection: $editedStartedAt
                    )
                }
            }

            detailSplitSection(title: L10n.tripTrimPointsSection) {
                trimStepperCell(
                    title: L10n.tripTrimHead,
                    value: $trimHeadCount,
                    range: 0...maxTrimHead
                )
            } right: {
                trimStepperCell(
                    title: L10n.tripTrimTail,
                    value: $trimTailCount,
                    range: 0...maxTrimTail
                )
            }

            detailSection(title: L10n.tripLocationOverrides) {
                compactTextField(L10n.tripStartPlaceName, text: $startPlaceNameText)
                favoritePlaceAction(
                    endpoint: .start,
                    coordinate: trip.startCoordinate,
                    accessibilityLabel: L10n.tripAddStartToFavorites
                )
                compactTextField(L10n.tripEndPlaceName, text: $endPlaceNameText)
                favoritePlaceAction(
                    endpoint: .end,
                    coordinate: trip.endCoordinate,
                    accessibilityLabel: L10n.tripAddEndToFavorites
                )
                compactTextField(L10n.tripStartAddress, text: $startAddressText)
                compactTextField(L10n.tripEndAddress, text: $endAddressText)
            }

            detailSplitSection(title: L10n.tripEditCategoryAndLabel) {
                detailMenuPicker(title: L10n.tripEditCategory, selection: $selectedCategoryID) {
                    ForEach(categories) { category in
                        Label(category.name, systemImage: category.systemImage)
                            .tag(category.id.uuidString)
                    }
                }
                .onChange(of: selectedCategoryID) { _, _ in
                    dismissNoteKeyboard()
                }
            } right: {
                detailMenuPicker(title: L10n.tripEditLabel, selection: $selectedLabel) {
                    Text(L10n.labelNone).tag("")
                    ForEach(TripLabelOption.allCases, id: \.rawValue) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .onChange(of: selectedLabel) { _, _ in
                    dismissNoteKeyboard()
                }
            }

            if !vehicles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.string("trip.edit.vehicle"))
                        .font(.subheadline.weight(.semibold))

                    detailMiniCard {
                        HStack(spacing: 10) {
                            if let selected = sortedDetailVehicles.first(where: { $0.id == selectedVehicleID }) {
                                VehicleAvatarView(
                                    systemImage: selected.systemImage,
                                    photoFileName: selected.photoFileName,
                                    size: 28,
                                    cornerRadius: 7,
                                    isElectricAccent: selected.fuelType == .electric
                                )
                            } else {
                                Image(systemName: "minus.circle")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, height: 28)
                            }

                            Picker(L10n.string("trip.edit.vehicle"), selection: $selectedVehicleID) {
                                Text(L10n.string("trip.edit.vehicle_none"))
                                    .tag(UUID?.none)
                                ForEach(sortedDetailVehicles) { vehicle in
                                    Text(vehicle.name)
                                        .tag(Optional(vehicle.id))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .buttonStyle(.plain)
                            .font(.callout)
                            .tint(.primary)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onChange(of: selectedVehicleID) { _, _ in
                                dismissNoteKeyboard()
                            }
                        }
                    }
                }
                .task(id: vehiclePhotoPrefetchID) {
                    await VehiclePhotoStore.shared.prefetch(vehicles: sortedDetailVehicles)
                }
            }

            detailSection(title: L10n.tripEditNote) {
                TextField(L10n.tripEditNotePlaceholder, text: $noteText, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($noteFocused)
                    .submitLabel(.done)
                    .glassInputField()
                    .onSubmit { dismissNoteKeyboard() }
            }

            Button(L10n.tripEditSave) {
                saveEdits()
                dismissNoteKeyboard()
            }
            .accessibilityIdentifier("tripDetail.save")
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .tint(TrailhoundBrandColors.brandBottom)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GlassTokens.listContentHorizontalInset)
        .padding(.bottom, 88)
    }

    private func panelGrabber(containerHeight: CGFloat) -> some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        dismissNoteKeyboard()
                        panelDragTranslation = value.translation.height
                    }
                    .onEnded { value in
                        snapPanelDetent(
                            containerHeight: containerHeight,
                            velocityY: value.predictedEndTranslation.height - value.translation.height
                        )
                    }
            )
            .accessibilityLabel(L10n.tripDetailPanelResize)
            .accessibilityHint(L10n.tripDetailPanelResizeHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityActions {
                Button(L10n.tripDetailPanelMoreMap) {
                    guard let lower = panelDetent.lower else { return }
                    withAnimation(reduceMotion ? nil : TrailhoundMotion.sheetRise) {
                        panelDetent = lower
                        panelDragTranslation = 0
                    }
                    refitMapForPanelDetent(lower)
                }
                Button(L10n.tripDetailPanelMoreDetails) {
                    guard let higher = panelDetent.higher else { return }
                    withAnimation(reduceMotion ? nil : TrailhoundMotion.sheetRise) {
                        panelDetent = higher
                        panelDragTranslation = 0
                    }
                    refitMapForPanelDetent(higher)
                }
            }
    }

    private var tripHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(resolvedViewModel.routeSummary)
                .font(.headline)
                .lineLimit(2)

            Text(resolvedViewModel.dateText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statsStrip: some View {
        let fuelCurrencyCode = settings.fuelCurrency.rawValue
        let metrics = resolvedViewModel.summaryMetrics
        let primaryIDs: Set<String> = ["duration", "distance", "maxSpeed"]
        let primaryRow = metrics.filter { primaryIDs.contains($0.id) }
        let secondaryRow = metrics.filter { !primaryIDs.contains($0.id) }

        VStack(spacing: 8) {
            if !primaryRow.isEmpty {
                statsMetricRow(metrics: primaryRow)
            }
            if !secondaryRow.isEmpty {
                statsCenteredMetricRow(metrics: secondaryRow)
            }
        }
        .id(fuelCurrencyCode)
    }

    private func statsMetricRow(metrics: [TripSummaryMetric]) -> some View {
        HStack(spacing: 8) {
            ForEach(metrics) { metric in
                statsMetricCard(for: metric)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statsCenteredMetricRow(metrics: [TripSummaryMetric]) -> some View {
        HStack(spacing: 8) {
            if metrics.count < 3 {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .layoutPriority(metrics.count == 2 ? 1 : 2)
            }

            ForEach(metrics) { metric in
                statsMetricCard(for: metric)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(2)
            }

            if metrics.count < 3 {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .layoutPriority(metrics.count == 2 ? 1 : 2)
            }
        }
    }

    private func statsMetricCard(for metric: TripSummaryMetric) -> some View {
        let progress = statCountProgress[metric.id] ?? (panelRisen ? 1 : 0)
        return VStack(alignment: .leading, spacing: 2) {
            Label(metric.title, systemImage: metric.icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(metric.formatted(progress: progress))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : TrailhoundMotion.snappy, value: progress)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 10, frozen: glassFrozen)
        .opacity(progress > 0.01 || reduceMotion ? 1 : 0.35)
        .scaleEffect(progress > 0.01 || reduceMotion ? 1 : 0.94)
    }

    private var speedChartCard: some View {
        let progress = speedChartRevealProgress

        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tripSpeedChart)
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(L10n.formatSpeedKmh(resolvedViewModel.speedChartMaxKmh))
                        .font(.caption2)
                    Spacer(minLength: 0)
                    Text(L10n.formatSpeedKmh(0))
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 120)

                SpeedChartRouteCanvas(
                    samples: resolvedViewModel.speedSamples,
                    maxKmh: resolvedViewModel.speedChartMaxKmh,
                    progress: progress,
                    tripStartedAt: trip.startedAt,
                    tripEndedAt: trip.endedAt ?? trip.startedAt,
                    sampleMedianIntervalSeconds: resolvedViewModel.speedSampleMedianIntervalSeconds
                )
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            }
        }
        .padding(12)
        .glassChrome(cornerRadius: 12, frozen: glassFrozen)
        .opacity(progress > 0.01 || reduceMotion ? 1 : 0.35)
        .scaleEffect(progress > 0.01 || reduceMotion ? 1 : 0.98)
    }

    private func tripTimePicker(title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Menu {
                DatePicker(title, selection: selection, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(TrailhoundBrandColors.brandBottom)
            } label: {
                detailTransparentPickerLabel(DateFormatters.tripDateOnly.string(from: selection.wrappedValue))
            }
            .tint(.primary)

            Menu {
                DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(width: 200, height: 120)
                    .tint(TrailhoundBrandColors.brandBottom)
            } label: {
                detailTransparentPickerLabel(DateFormatters.tripTime.string(from: selection.wrappedValue))
            }
            .tint(.primary)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func detailTransparentPickerLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func trimStepperCell(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                detailCompactStepButton(systemImage: "minus") {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
                }
                .disabled(value.wrappedValue <= range.lowerBound)

                Text("\(value.wrappedValue)")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)

                detailCompactStepButton(systemImage: "plus") {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
                }
                .disabled(value.wrappedValue >= range.upperBound)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailCompactStepButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .frame(width: 26, height: 26)
                .glassField(cornerRadius: 6)
        }
        .buttonStyle(.plain)
    }

    private func detailMenuPicker<Selection: Hashable, Content: View>(
        title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Picker(title, selection: selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .buttonStyle(.plain)
                .font(.callout)
                .tint(.primary)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func detailMiniCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .glassChrome(cornerRadius: 12, frozen: glassFrozen)
    }

    private func detailSplitSection<Left: View, Right: View>(
        title: String,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .top, spacing: 10) {
                detailMiniCard(content: left)
                    .frame(minWidth: 0, maxWidth: .infinity)
                detailMiniCard(content: right)
                    .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
    }

    private func detailSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .glassChrome(cornerRadius: 12, frozen: glassFrozen)
        }
    }

    private func compactTextField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .glassInputField()
        }
    }

    @ViewBuilder
    private func favoritePlaceAction(
        endpoint: FavoritePlaceSheetItem.Endpoint,
        coordinate: CLLocationCoordinate2D?,
        accessibilityLabel: String
    ) -> some View {
        if let coordinate {
            let existing = places.first(where: { $0.contains(coordinate) })
            Button {
                dismissNoteKeyboard()
                if let existing {
                    favoritePlaceSheet = FavoritePlaceSheetItem(
                        mode: .edit(existing.id),
                        endpoint: endpoint
                    )
                } else {
                    favoritePlaceSheet = FavoritePlaceSheetItem(
                        mode: .create(draft(for: endpoint, coordinate: coordinate)),
                        endpoint: endpoint
                    )
                }
            } label: {
                Label(
                    existing == nil ? L10n.tripAddToFavorites : L10n.placeAlreadySaved,
                    systemImage: existing == nil ? "star" : "star.fill"
                )
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(existing == nil ? accessibilityLabel : L10n.tripEditFavoritePlace)
        }
    }

    private func draft(
        for endpoint: FavoritePlaceSheetItem.Endpoint,
        coordinate: CLLocationCoordinate2D
    ) -> PlaceDraft {
        let placeName: String
        let address: String?
        switch endpoint {
        case .start:
            placeName = startPlaceNameText.trimmingCharacters(in: .whitespacesAndNewlines)
            address = startAddressText.trimmingCharacters(in: .whitespacesAndNewlines)
        case .end:
            placeName = endPlaceNameText.trimmingCharacters(in: .whitespacesAndNewlines)
            address = endAddressText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let resolvedName: String
        if !placeName.isEmpty {
            resolvedName = placeName
        } else if let address, !address.isEmpty {
            resolvedName = address
        } else {
            resolvedName = ""
        }

        return PlaceDraft(
            name: resolvedName,
            coordinate: coordinate,
            address: (address?.isEmpty == false) ? address : nil,
            kind: .other
        )
    }

    @ViewBuilder
    private func favoritePlacePicker(for item: FavoritePlaceSheetItem) -> some View {
        switch item.mode {
        case .create(let draft):
            PlacePickerView(draft: draft) { savedName in
                applyFavoritePlaceName(savedName, to: item.endpoint)
            }
        case .edit(let placeID):
            if let place = places.first(where: { $0.id == placeID }) {
                PlacePickerView(editingPlace: place) { savedName in
                    applyFavoritePlaceName(savedName, to: item.endpoint)
                }
            } else {
                Text(L10n.placeAlreadySaved)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func applyFavoritePlaceName(_ name: String, to endpoint: FavoritePlaceSheetItem.Endpoint) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch endpoint {
        case .start:
            startPlaceNameText = trimmed
            trip.startPlaceName = trimmed
        case .end:
            endPlaceNameText = trimmed
            trip.endPlaceName = trimmed
        }

        TripDerivedMetrics.refreshSearchIndex(
            for: trip,
            places: places,
            privacyRadius: settings.privacyRadiusMeters
        )
        tripDetailViewModel = TripDetailViewModel(
            trip: trip,
            places: places,
            privacyRadius: settings.privacyRadiusMeters,
            displayPieces: tripDetailViewModel?.displayPieces
        )
        try? modelContext.save()
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

    private var maxTrimHead: Int {
        max(0, recordedPointCount - trimTailCount - 2)
    }

    private var maxTrimTail: Int {
        max(0, recordedPointCount - trimHeadCount - 2)
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
        let drawCasing = progress >= 0.999
        let showStops = forceShowAllStops || showAllStops || progress >= 0.999
        let revealedSegments = resolvedViewModel.revealedSpeedColoredSegments(progress: progress)
        let revealedFallback = resolvedViewModel.revealedFallbackCoordinates(progress: progress)
        let revealedItems = revealedSegments.map { segment in
            TripDetailRevealedRouteSegment(
                id: "\(segment.id)",
                coordinates: segment.coordinates,
                color: segment.color
            )
        }

        TripDetailMapLayer(
            style: mapStyle,
            interactive: interactive,
            routeRevealProgress: progress,
            drawCasing: drawCasing,
            revealedItems: revealedItems,
            revealedFallback: revealedFallback,
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

    private func dismissNoteKeyboard() {
        noteFocused = false
        KeyboardDismiss.dismiss()
    }

    private func saveEdits() {
        // Captured before the edit lands: date, category and vehicle all decide which rollup
        // bucket this trip counted toward, and any of them may be about to change.
        let previousRollup = TripRollupService.snapshot(of: trip)

        trip.note = noteText.isEmpty ? nil : noteText
        trip.label = selectedLabel.isEmpty ? nil : selectedLabel
        trip.categoryID = selectedCategoryID
        let vehicle = selectedVehicleID.flatMap { VehicleResolver.vehicle(withID: $0, in: modelContext) }
        VehicleResolver.assign(vehicle: vehicle, to: trip)
        trip.estimatedFuelCost = FuelCostCalculator.estimateCost(
            distanceMeters: trip.distanceMeters,
            vehicle: vehicle
        )
        trip.startAddress = startAddressText.isEmpty ? nil : startAddressText
        trip.endAddress = endAddressText.isEmpty ? nil : endAddressText
        trip.startPlaceName = startPlaceNameText.isEmpty ? nil : startPlaceNameText
        trip.endPlaceName = endPlaceNameText.isEmpty ? nil : endPlaceNameText
        trip.startedAt = editedStartedAt
        if trip.endedAt != nil {
            trip.endedAt = max(editedEndedAt, editedStartedAt)
        }
        applyGPSTrimIfNeeded()
        // Covers both edits that moved the trip's dates and trims that replaced its points.
        TripDerivedMetrics.recompute(
            for: trip,
            places: places,
            privacyRadius: settings.privacyRadiusMeters
        )
        TripRollupService.update(trip, from: previousRollup, in: modelContext)
        originalNoteText = noteText
        try? modelContext.save()
        ToastPresenter.shared.show(.tripSaved)
    }

    private func applyGPSTrimIfNeeded() {
        guard trimHeadCount > 0 || trimTailCount > 0 else { return }

        var sorted = trip.sortedPoints
        guard sorted.count > trimHeadCount + trimTailCount else { return }

        if trimHeadCount > 0 {
            sorted.removeFirst(trimHeadCount)
        }
        if trimTailCount > 0 {
            sorted.removeLast(trimTailCount)
        }

        for point in trip.points {
            modelContext.delete(point)
        }
        trip.points.removeAll()

        var distance: Double = 0
        var previousLocation: CLLocation?
        for (index, oldPoint) in sorted.enumerated() {
            let point = TripPoint(
                timestamp: oldPoint.timestamp,
                latitude: oldPoint.latitude,
                longitude: oldPoint.longitude,
                sequence: index,
                speedMps: oldPoint.speedMps,
                trip: trip
            )
            trip.points.append(point)
            modelContext.insert(point)

            let location = CLLocation(latitude: oldPoint.latitude, longitude: oldPoint.longitude)
            if let previousLocation {
                distance += location.distance(from: previousLocation)
            }
            previousLocation = location
        }

        trip.distanceMeters = distance
        trip.invalidatePointCaches()
        TripDetailViewModel.invalidateSpeedSegmentCache(for: trip.id)
        TripRoutePathCache.shared.remove(for: trip.id)
        DevLog.shared.log(.tripDetail, "gps trim trip=\(trip.id.uuidString.prefix(8)) head=\(trimHeadCount) tail=\(trimTailCount)")
        trimHeadCount = 0
        trimTailCount = 0
        recordedPointCount = trip.points.count
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

private struct TripStopEditRow: View {
    @Bindable var stop: TripStop
    @State private var startedAt: Date = Date()
    @State private var durationMinutes: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker(L10n.tripStartedAt, selection: $startedAt)
                .labelsHidden()
                .datePickerStyle(.compact)
                .buttonStyle(.plain)
                .tint(TrailhoundBrandColors.brandBottom)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassField(cornerRadius: 8)
                .onChange(of: startedAt) { _, newValue in
                    stop.startedAt = newValue
                }

            Stepper(
                "\(L10n.duration): \(DateFormatters.formatDuration(stop.durationSeconds))",
                value: $durationMinutes,
                in: 1...240
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassField(cornerRadius: 8)
            .onChange(of: durationMinutes) { _, newValue in
                stop.durationSeconds = TimeInterval(newValue * 60)
            }
        }
        .onAppear {
            startedAt = stop.startedAt
            durationMinutes = max(1, Int(stop.durationSeconds / 60))
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

private struct SpeedChartRouteCanvas: View {
    let samples: [(id: Int, date: Date, speedKmh: Double)]
    let maxKmh: Double
    let progress: Double
    let tripStartedAt: Date
    let tripEndedAt: Date
    /// Typical spacing between plotted samples; the gap threshold scales off it.
    let sampleMedianIntervalSeconds: TimeInterval

    private static let minimumGapBreakSeconds: TimeInterval = 90

    /// A fixed threshold breaks the line on sparsely sampled trips, where six times the normal
    /// spacing is what actually signals a recording gap.
    private var gapBreakSeconds: TimeInterval {
        max(Self.minimumGapBreakSeconds, sampleMedianIntervalSeconds * 6)
    }

    private var brandColor: Color { TrailhoundBrandColors.brandBottom }

    var body: some View {
        Canvas { context, size in
            let revealed = revealedSamples(progress: progress)
            let pointGroups = projectedPointGroups(for: revealed, in: size)
            guard !pointGroups.isEmpty else { return }

            let baselineY = size.height - 2

            for points in pointGroups {
                guard points.count >= 1 else { continue }

                if points.count == 1 {
                    var dot = Path()
                    dot.addEllipse(in: CGRect(x: points[0].x - 2, y: points[0].y - 2, width: 4, height: 4))
                    context.fill(dot, with: .color(brandColor))
                    continue
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
            }

            if progress < 0.995, let tip = pointGroups.last?.last {
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

    private func revealedSamples(progress: Double) -> [(date: Date, speedKmh: Double)] {
        guard samples.count >= 2 else {
            return samples.map { ($0.date, $0.speedKmh) }
        }

        let clamped = min(1, max(0, progress))
        if clamped <= 0 {
            return [(samples[0].date, samples[0].speedKmh)]
        }
        if clamped >= 1 {
            return samples.map { ($0.date, $0.speedKmh) }
        }

        let segmentCount = samples.count - 1
        let exact = Double(segmentCount) * clamped
        let index = min(segmentCount - 1, Int(exact))
        let fraction = exact - Double(index)
        var result = samples.prefix(index + 1).map { ($0.date, $0.speedKmh) }
        let start = samples[index]
        let end = samples[index + 1]
        let startTime = start.date.timeIntervalSince1970
        let endTime = end.date.timeIntervalSince1970
        result.append((
            date: Date(timeIntervalSince1970: startTime + (endTime - startTime) * fraction),
            speedKmh: start.speedKmh + (end.speedKmh - start.speedKmh) * fraction
        ))
        return result
    }

    private func projectedPointGroups(
        for samples: [(date: Date, speedKmh: Double)],
        in size: CGSize
    ) -> [[CGPoint]] {
        let points = projectedPoints(for: samples, in: size)
        guard points.count >= 2 else {
            return points.isEmpty ? [] : [points]
        }

        var groups: [[CGPoint]] = []
        var current = [points[0]]
        for index in 1..<points.count {
            let gap = samples[index].date.timeIntervalSince(samples[index - 1].date)
            if gap > gapBreakSeconds {
                groups.append(current)
                current = [points[index]]
            } else {
                current.append(points[index])
            }
        }
        groups.append(current)
        return groups
    }

    private func projectedPoints(
        for samples: [(date: Date, speedKmh: Double)],
        in size: CGSize
    ) -> [CGPoint] {
        guard !samples.isEmpty else { return [] }

        let dateSpan = max(tripEndedAt.timeIntervalSince(tripStartedAt), 1)
        let inset: CGFloat = 2
        let drawWidth = max(size.width - inset * 2, 1)
        let drawHeight = max(size.height - inset * 2, 1)
        let baselineY = size.height - inset
        let speedMax = max(maxKmh, 1)

        return samples.map { sample in
            let xFraction = sample.date.timeIntervalSince(tripStartedAt) / dateSpan
            let yFraction = min(1, max(0, sample.speedKmh / speedMax))
            return CGPoint(
                x: inset + CGFloat(xFraction) * drawWidth,
                y: baselineY - CGFloat(yFraction) * drawHeight
            )
        }
    }
}

#Preview {
    NavigationStack {
        TripDetailView(trip: PreviewData.sampleTrip)
    }
    .modelContainer(PreviewData.shared.container)
    .environment(NetworkMonitor.shared)
}
