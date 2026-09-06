import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

enum TravelJournalPanelDetent: Equatable {
    case compact
    case expanded
}

/// Resting travel-detail sheet is a compact summary so the map stays the hero.
/// Drag snaps between compact and a list detent that still leaves a map peek.
enum TravelJournalPanelLayout {
    static let compactHeightFraction: CGFloat = 0.32
    static let expandedHeightFraction: CGFloat = 0.72
    static let compactMinimum: CGFloat = 292
    static let rubberBand: CGFloat = 28

    static func compactHeight(containerHeight: CGFloat) -> CGFloat {
        guard containerHeight > 0 else { return 0 }
        let preferred = containerHeight * compactHeightFraction
        let ceiling = containerHeight * 0.40
        return min(max(preferred, compactMinimum), ceiling)
    }

    static func expandedHeight(containerHeight: CGFloat, mapPeek: CGFloat) -> CGFloat {
        guard containerHeight > 0 else { return 0 }
        let preferred = containerHeight * expandedHeightFraction
        let capped = max(0, containerHeight - max(mapPeek, 0))
        return min(preferred, capped)
    }

    static func height(
        for detent: TravelJournalPanelDetent,
        containerHeight: CGFloat,
        mapPeek: CGFloat
    ) -> CGFloat {
        switch detent {
        case .compact:
            return compactHeight(containerHeight: containerHeight)
        case .expanded:
            return expandedHeight(containerHeight: containerHeight, mapPeek: mapPeek)
        }
    }

    /// `translation` is SwiftUI drag translation: positive Y shrinks the bottom sheet.
    static func draggedHeight(
        detent: TravelJournalPanelDetent,
        translation: CGFloat,
        containerHeight: CGFloat,
        mapPeek: CGFloat
    ) -> CGFloat {
        let compact = compactHeight(containerHeight: containerHeight)
        let expanded = expandedHeight(containerHeight: containerHeight, mapPeek: mapPeek)
        let base = height(for: detent, containerHeight: containerHeight, mapPeek: mapPeek)
        return clampedHeight(base - translation, compact: compact, expanded: expanded)
    }

    static func clampedHeight(_ height: CGFloat, compact: CGFloat, expanded: CGFloat) -> CGFloat {
        min(max(height, compact - rubberBand), expanded + rubberBand)
    }

    static func snappedDetent(
        predictedTranslation: CGFloat,
        from detent: TravelJournalPanelDetent,
        containerHeight: CGFloat,
        mapPeek: CGFloat
    ) -> TravelJournalPanelDetent {
        let compact = compactHeight(containerHeight: containerHeight)
        let expanded = expandedHeight(containerHeight: containerHeight, mapPeek: mapPeek)
        let base = height(for: detent, containerHeight: containerHeight, mapPeek: mapPeek)
        let projected = clampedHeight(base - predictedTranslation, compact: compact, expanded: expanded)
        let mid = (compact + expanded) / 2
        if predictedTranslation < -240 { return .expanded }
        if predictedTranslation > 240 { return .compact }
        return projected >= mid ? .expanded : .compact
    }
}

struct TravelJournalDetailView: View {
    @Bindable var journal: TravelJournal
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var places: [SavedPlace]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cameraBox = TripDetailMapCameraBox()
    @State private var selectedTripID: UUID?
    @State private var overlays: [TravelJournalRouteOverlay] = []
    @State private var selectedSegments: [TripDetailRevealedRouteSegment] = []
    @State private var fitCoordinates: [CLLocationCoordinate2D] = []
    @State private var isMapExpanded = false
    @State private var panelDetent: TravelJournalPanelDetent = .compact
    @State private var dragTranslation: CGFloat = 0
    @State private var panelRisen = false
    @State private var editorDraft: TravelJournalEditorDraft?
    @State private var openTrip: Trip?
    @State private var mapStyleOverride: TripDetailMapStyle?
    @State private var mapViewportSize: CGSize = CGSize(width: 390, height: 844)
    @State private var mapTopChromePoints: CGFloat = 96
    @State private var mapBottomChromePoints: CGFloat = 83
    @State private var mapRefitTask: Task<Void, Never>?

    private var members: [Trip] {
        journal.trips.filter { $0.endedAt != nil }.sorted { $0.startedAt > $1.startedAt }
    }

    private var mapStyle: TripDetailMapStyle {
        mapStyleOverride ?? .matching(colorScheme)
    }

    private var panelVisible: Bool { panelRisen && !isMapExpanded }

    var body: some View {
        mapRoot
            .ignoresSafeArea(edges: .bottom)
            .glassNavigationChrome()
            .navigationTitle(journal.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { mapExpandToolbar }
            .navigationDestination(isPresented: openTripBinding) {
                if let trip = openTrip {
                    TripDetailView(trip: trip)
                }
            }
            .sheet(item: $editorDraft) { draft in
                TravelJournalEditorSheet(draft: draft)
            }
            .task(id: journal.id) {
                await playPanelEntrance()
            }
            .onChange(of: selectedTripID) { _, _ in
                Task { await loadRoutes() }
            }
            .onChange(of: journal.tripCount) { _, _ in
                Task { await loadRoutes() }
            }
            .onChange(of: panelDetent) { _, _ in
                scheduleMapRefit(delayMilliseconds: 120)
            }
    }

    private var mapRoot: some View {
        ZStack {
            AtmosphericBackground()
            GeometryReader { geometry in
                mapAndPanel(in: geometry)
            }
        }
    }

    private var openTripBinding: Binding<Bool> {
        Binding(
            get: { openTrip != nil },
            set: { if !$0 { openTrip = nil } }
        )
    }

    private var mapExpandIconName: String {
        isMapExpanded
            ? "arrow.down.right.and.arrow.up.left"
            : "arrow.up.left.and.arrow.down.right"
    }

    private var mapExpandAccessibilityLabel: String {
        isMapExpanded
            ? L10n.string("journal.map.collapse")
            : L10n.string("journal.map.expand")
    }

    @ToolbarContentBuilder
    private var mapExpandToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: toggleMapExpanded) {
                GlassNavCircleIcon(systemName: mapExpandIconName)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mapExpandAccessibilityLabel)
        }
        .hideSharedToolbarBackgroundIfAvailable()
    }

    private func mapAndPanel(in geometry: GeometryProxy) -> some View {
        let mapPeek = mapTopChromePoints + 24
        let panelHeight = livePanelHeight(
            containerHeight: geometry.size.height,
            mapPeek: mapPeek
        )
        return ZStack(alignment: .bottom) {
            TravelJournalMapLayer(
                style: mapStyle,
                overlays: overlays,
                selectedSegments: selectedSegments,
                cameraBox: cameraBox
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            editPanel(
                height: panelHeight,
                mapPeek: mapPeek,
                containerHeight: geometry.size.height
            )
        }
        .onAppear {
            refreshMapChromeInsets(from: geometry)
        }
        .onChange(of: geometry.size) { _, _ in
            refreshMapChromeInsets(from: geometry)
            scheduleMapRefit(animated: false)
        }
    }

    private func editPanel(
        height: CGFloat,
        mapPeek: CGFloat,
        containerHeight: CGFloat
    ) -> some View {
        TravelJournalEditPanel(
            journal: journal,
            trips: members,
            selectedTripID: selectedTripID,
            places: places,
            restHeight: height,
            isExpanded: panelDetent == .expanded,
            reduceMotion: reduceMotion,
            onSelectTrip: { selectedTripID = $0 },
            onOpenTrip: { openTrip = $0 },
            onRemoveTrip: removeFromJournal,
            onEdit: { editorDraft = .edit(journal) },
            onToggleExpanded: { togglePanelDetent() },
            onGrabberDragChanged: { translation in
                dragTranslation = translation
            },
            onGrabberDragEnded: { predicted in
                snapPanel(
                    predictedTranslation: predicted,
                    containerHeight: containerHeight,
                    mapPeek: mapPeek
                )
            }
        )
        .frame(maxWidth: .infinity)
        .background {
            AtmosphericBackground(style: .lightweight)
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
        .offset(y: panelVisible ? 0 : height + 24)
        .opacity(panelVisible ? 1 : 0)
        .animation(reduceMotion ? nil : TrailhoundMotion.sheetRise, value: panelRisen)
        .animation(reduceMotion ? nil : mapExpandAnimation, value: isMapExpanded)
        .allowsHitTesting(panelVisible)
    }

    private var mapExpandAnimation: Animation {
        isMapExpanded ? TrailhoundMotion.mapExpand : TrailhoundMotion.mapCollapse
    }

    @MainActor
    private func playPanelEntrance() async {
        panelRisen = false
        panelDetent = .compact
        dragTranslation = 0
        await loadRoutes()
        withAnimation(reduceMotion ? nil : TrailhoundMotion.sheetRise) {
            panelRisen = true
        }
        scheduleMapRefit(delayMilliseconds: 80)
    }

    private func livePanelHeight(containerHeight: CGFloat, mapPeek: CGFloat) -> CGFloat {
        TravelJournalPanelLayout.draggedHeight(
            detent: panelDetent,
            translation: dragTranslation,
            containerHeight: containerHeight,
            mapPeek: mapPeek
        )
    }

    private func togglePanelDetent() {
        TrailhoundHaptics.selection()
        withAnimation(reduceMotion ? nil : TrailhoundMotion.sheetRise) {
            panelDetent = panelDetent == .compact ? .expanded : .compact
            dragTranslation = 0
        }
    }

    private func snapPanel(
        predictedTranslation: CGFloat,
        containerHeight: CGFloat,
        mapPeek: CGFloat
    ) {
        let next = TravelJournalPanelLayout.snappedDetent(
            predictedTranslation: predictedTranslation,
            from: panelDetent,
            containerHeight: containerHeight,
            mapPeek: mapPeek
        )
        if next != panelDetent {
            TrailhoundHaptics.selection()
        }
        withAnimation(reduceMotion ? nil : TrailhoundMotion.sheetRise) {
            panelDetent = next
            dragTranslation = 0
        }
    }

    private func toggleMapExpanded() {
        let expanding = !isMapExpanded
        TrailhoundHaptics.selection()
        withAnimation(reduceMotion ? nil : (expanding ? TrailhoundMotion.mapExpand : TrailhoundMotion.mapCollapse)) {
            isMapExpanded = expanding
        }
        scheduleMapRefit(delayMilliseconds: 40)
    }

    private func removeFromJournal(_ trip: Trip) {
        TrailhoundHaptics.destructive()
        TravelJournalTotals.assign(trip: trip, to: nil, in: modelContext)
        if selectedTripID == trip.id {
            selectedTripID = nil
        }
        try? modelContext.save()
    }

    private func loadRoutes() async {
        let trips = members
        guard !trips.isEmpty else {
            overlays = []
            selectedSegments = []
            fitCoordinates = []
            return
        }

        var raw: [(trip: Trip, coordinates: [CLLocationCoordinate2D], samples: [[RouteSample]])] = []
        for trip in trips {
            let pieces = await TripRoutePathCache.shared.path(for: trip, container: modelContext.container)
            let coordinates = pieces.flatMap { $0.map(\.coordinate) }
            raw.append((trip, coordinates, pieces))
        }

        let counts = raw.map(\.coordinates.count)
        let useOverview = raw.count >= TravelJournalMapBudget.overviewTripCount
        let allocated = TravelJournalMapBudget.allocate(pointCounts: counts)

        if useOverview {
            let hull = TravelJournalMapBudget.boundingPolyline(from: raw.map(\.coordinates))
            overlays = [
                TravelJournalRouteOverlay(
                    id: journal.id,
                    coordinates: hull,
                    color: TrailhoundBrandColors.brandBottom.opacity(0.55),
                    isSelected: false
                )
            ]
            selectedSegments = []
            fitCoordinates = hull
            applyFittedCamera(animated: false)
            return
        }

        let domainKeys = raw.map { $0.trip.id.uuidString }
        var nextOverlays: [TravelJournalRouteOverlay] = []
        var nextSelected: [TripDetailRevealedRouteSegment] = []
        let selectedID = selectedTripID ?? raw.first?.trip.id

        for (index, item) in raw.enumerated() {
            let sampled = TravelJournalMapBudget.downsample(item.coordinates, to: allocated[index])
            let isSelected = item.trip.id == selectedID
            let color = StatsChartTheme.sliceColor(
                forStableKey: item.trip.id.uuidString,
                durationStyle: false,
                domainKeys: domainKeys,
                palette: AppSettings.shared.shellPalette,
                scheme: colorScheme
            )
            nextOverlays.append(
                TravelJournalRouteOverlay(
                    id: item.trip.id,
                    coordinates: sampled,
                    color: isSelected ? color.opacity(0.35) : color.opacity(0.4),
                    isSelected: false
                )
            )
            if isSelected {
                let segments = SpeedColoredSegmentBuilder.build(pieces: item.samples)
                nextSelected = segments.map {
                    TripDetailRevealedRouteSegment(
                        id: "\(item.trip.id.uuidString)-\($0.id)",
                        coordinates: $0.coordinates,
                        color: $0.color
                    )
                }
            }
        }

        overlays = nextOverlays
        selectedSegments = nextSelected
        if selectedTripID == nil {
            selectedTripID = selectedID
        }
        if let selected = raw.first(where: { $0.trip.id == selectedID }), !selected.coordinates.isEmpty {
            fitCoordinates = selected.coordinates
        } else {
            fitCoordinates = raw.flatMap(\.coordinates)
        }
        applyFittedCamera(animated: false)
    }

    private func refreshMapChromeInsets(from geometry: GeometryProxy) {
        mapViewportSize = geometry.size
        let window = windowSafeInsets
        let topSafe = max(geometry.safeAreaInsets.top, window.top, 54)
        mapTopChromePoints = topSafe + 44
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
        let horizontal = max(size.width * 0.06, 16)
        if isMapExpanded {
            let top = max(mapTopChromePoints, 96)
            let bottom = max(mapBottomChromePoints, 83) + 16
            return UIEdgeInsets(top: top, left: horizontal, bottom: bottom, right: horizontal)
        }
        let top = max(mapTopChromePoints, 96)
        let bottom = max(panelHeight, 0) + 24
        return UIEdgeInsets(top: top, left: horizontal, bottom: bottom, right: horizontal)
    }

    private func applyFittedCamera(animated: Bool) {
        let height: CGFloat
        if isMapExpanded {
            height = 0
        } else {
            height = TravelJournalPanelLayout.height(
                for: panelDetent,
                containerHeight: mapViewportSize.height,
                mapPeek: mapTopChromePoints + 24
            )
        }
        guard let region = TripDetailViewModel.regionFitting(
            coordinates: fitCoordinates,
            mapSize: mapViewportSize,
            edgePadding: mapEdgePadding(panelHeight: height),
            margin: isMapExpanded ? 1.18 : 1.2
        ) else { return }

        let position = MapCameraPosition.region(region)
        if animated, !reduceMotion {
            withAnimation(TrailhoundMotion.gentle) {
                cameraBox.position = position
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                cameraBox.position = position
            }
        }
    }

    private func scheduleMapRefit(animated: Bool = true, delayMilliseconds: UInt64 = 160) {
        mapRefitTask?.cancel()
        mapRefitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled else { return }
            applyFittedCamera(animated: animated)
        }
    }
}
