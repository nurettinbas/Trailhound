import CoreLocation
import MapKit
import SwiftData
import SwiftUI

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
    @State private var isMapExpanded = false
    @State private var editorDraft: TravelJournalEditorDraft?
    @State private var openTrip: Trip?
    @State private var mapStyleOverride: TripDetailMapStyle?

    private var members: [Trip] {
        journal.trips.filter { $0.endedAt != nil }.sorted { $0.startedAt > $1.startedAt }
    }

    private var mapStyle: TripDetailMapStyle {
        mapStyleOverride ?? .matching(colorScheme)
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()

            GeometryReader { geometry in
                let panelHeight = geometry.size.height * 0.46
                ZStack(alignment: .bottom) {
                    TravelJournalMapLayer(
                        style: mapStyle,
                        overlays: overlays,
                        selectedSegments: selectedSegments,
                        cameraBox: cameraBox
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !isMapExpanded {
                        TravelJournalEditPanel(
                            journal: journal,
                            trips: members,
                            selectedTripID: selectedTripID,
                            places: places,
                            restHeight: panelHeight,
                            reduceMotion: reduceMotion,
                            onSelectTrip: { selectedTripID = $0 },
                            onOpenTrip: { openTrip = $0 },
                            onRemoveTrip: removeFromJournal,
                            onEdit: { editorDraft = .edit(journal) }
                        )
                    }
                }
            }
        }
        .navigationTitle(journal.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(reduceMotion ? nil : TrailhoundMotion.mapExpand) {
                        isMapExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isMapExpanded ? "rectangle.compress.vertical" : "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel(isMapExpanded ? L10n.string("journal.map.collapse") : L10n.string("journal.map.expand"))
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { openTrip != nil },
            set: { if !$0 { openTrip = nil } }
        )) {
            if let trip = openTrip {
                TripDetailView(trip: trip)
            }
        }
        .sheet(item: $editorDraft) { draft in
            TravelJournalEditorSheet(draft: draft)
        }
        .task(id: journal.id) {
            await loadRoutes()
        }
        .onChange(of: selectedTripID) { _, _ in
            Task { await loadRoutes() }
        }
        .onChange(of: journal.tripCount) { _, _ in
            Task { await loadRoutes() }
        }
    }

    private func removeFromJournal(_ trip: Trip) {
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
            fit(coordinates: hull, panelFraction: isMapExpanded ? 0.12 : 0.46)
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
                domainKeys: domainKeys
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
        fit(coordinates: raw.flatMap(\.coordinates), panelFraction: isMapExpanded ? 0.12 : 0.46)
    }

    private func fit(coordinates: [CLLocationCoordinate2D], panelFraction: Double) {
        guard let region = Self.region(covering: coordinates, panelFraction: panelFraction) else { return }
        cameraBox.position = .region(region)
    }

    private static func region(
        covering coordinates: [CLLocationCoordinate2D],
        panelFraction: Double
    ) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let latPad = max((maxLat - minLat) * 0.18, 0.01)
        let lonPad = max((maxLon - minLon) * 0.18, 0.01)
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2 - (maxLat - minLat) * panelFraction * 0.15,
            longitude: (minLon + maxLon) / 2
        )
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: (maxLat - minLat) + latPad * 2,
                longitudeDelta: (maxLon - minLon) + lonPad * 2
            )
        )
    }
}
