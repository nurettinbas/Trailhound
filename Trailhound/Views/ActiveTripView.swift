import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct RecordingVehiclePicker: View {
    let vehicles: [VehicleProfile]
    let selectedVehicleID: UUID?
    let onSelect: (UUID) -> Void
    var compact: Bool = false

    private var sortedVehicles: [VehicleProfile] {
        vehicles.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var selectedVehicle: VehicleProfile? {
        guard let selectedVehicleID else { return nil }
        return vehicles.first(where: { $0.id == selectedVehicleID })
    }

    private var selectedName: String {
        selectedVehicle?.name ?? L10n.string("recording.vehicle.choose")
    }

    private var selectedSystemImage: String {
        selectedVehicle?.systemImage ?? VehicleIconOption.default.rawValue
    }

    var body: some View {
        Menu {
            ForEach(sortedVehicles) { vehicle in
                Button {
                    onSelect(vehicle.id)
                    TrailhoundHaptics.selection()
                } label: {
                    if vehicle.id == selectedVehicleID {
                        Label(vehicle.name, systemImage: "checkmark")
                    } else {
                        Label(vehicle.name, systemImage: vehicle.systemImage)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selectedSystemImage)
                    .font(compact ? .caption.weight(.semibold) : .subheadline)
                if !compact {
                    Text(selectedName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(compact ? Color.white.opacity(0.9) : TrailhoundBrandColors.brandBottom)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 5 : 6)
            .background(compact ? Color.white.opacity(0.14) : TrailhoundBrandColors.brandBottom.opacity(0.1))
            .clipShape(Capsule())
        }
        .accessibilityLabel(L10n.string("recording.vehicle.accessibility"))
        .accessibilityValue(selectedName)
    }
}

enum RecordingMorphID {
    static let statusChip = "recording.statusChip"
    static let car = "recording.car"
}

struct ActiveTripView: View {
    var morphNamespace: Namespace.ID?
    var morphID: UUID?
    /// Whole-card fade-in on trip start.
    var playEntranceReveal: Bool = false
    var onEntranceFinished: (() -> Void)?
    var onStop: (() -> Void)?

    @Environment(TripRecordingService.self) private var recordingService
    @Environment(LocationService.self) private var locationService
    @Environment(\.modelContext) private var modelContext
    @Query private var vehicles: [VehicleProfile]
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var breadcrumbCamera: MapCameraPosition = .automatic
    @State private var cardReveal: CGFloat = 1
    @State private var carDriveIn: CGFloat = 1
    @State private var detailsReveal: CGFloat = 1
    @State private var didRunEntrance = false

    init(
        morphNamespace: Namespace.ID? = nil,
        morphID: UUID? = nil,
        playEntranceReveal: Bool = false,
        onEntranceFinished: (() -> Void)? = nil,
        onStop: (() -> Void)? = nil
    ) {
        self.morphNamespace = morphNamespace
        self.morphID = morphID
        self.playEntranceReveal = playEntranceReveal
        self.onEntranceFinished = onEntranceFinished
        self.onStop = onStop
        let settled = !playEntranceReveal
        _cardReveal = State(initialValue: settled ? 1 : 0)
        _carDriveIn = State(initialValue: settled ? 1 : 0)
        _detailsReveal = State(initialValue: settled ? 1 : 0)
    }

    private var isPaused: Bool {
        recordingService.state == .paused
    }

    private var cardVisible: Bool {
        cardReveal > 0.02
    }

    private var speedText: String {
        let kmh = Int(max(0, recordingService.currentSpeedMps) * 3.6)
        return "\(kmh) \(L10n.speedKmh)"
    }

    private var elapsedText: String {
        DateFormatters.formatDuration(recordingService.elapsedTime)
    }

    private var distanceText: String {
        DateFormatters.formatDistance(recordingService.currentDistanceMeters)
    }

    private var statusText: String {
        isPaused ? L10n.recordingPaused : L10n.recordingStarted
    }

    private var breadcrumbCoordinates: [CLLocationCoordinate2D] {
        recordingService.liveBreadcrumbCoordinates
    }

    private var liveDotCoordinate: CLLocationCoordinate2D? {
        locationService.lastLocation?.coordinate ?? breadcrumbCoordinates.last
    }

    var body: some View {
        if recordingService.state.isActiveSession {
            recordingCard
        } else {
            EmptyView()
        }
    }

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow

            HStack(alignment: .center, spacing: 10) {
                RecordingCarAnimationView(
                    compact: true,
                    isAnimating: !isPaused && cardVisible,
                    driveInProgress: carDriveIn
                )
                    .frame(maxWidth: .infinity)
                    .matchedGeometryEffectIfAvailable(
                        stringID: RecordingMorphID.car,
                        namespace: morphNamespace,
                        isSource: true
                    )

                liveBreadcrumbMap
                    .frame(width: 96, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    }
                    .opacity(detailsReveal)
                    .scaleEffect(0.92 + 0.08 * detailsReveal)
                    .matchedGeometryEffectIfAvailable(
                        id: morphID,
                        namespace: morphNamespace,
                        isSource: true
                    )
            }
            .frame(height: 72)

            HStack(alignment: .top, spacing: 8) {
                statPill(icon: "clock.fill", label: L10n.duration, text: elapsedText)
                statPill(icon: "speedometer", label: L10n.currentSpeed, text: speedText)
                statPill(
                    icon: "location.fill",
                    label: L10n.string("label.distance"),
                    text: distanceText
                )
            }
            .opacity(detailsReveal)
            .offset(y: (1 - detailsReveal) * 10)

            actionsRow
                .opacity(detailsReveal)
                .offset(y: (1 - detailsReveal) * 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RecordingCardStyle.glassSurface(isPaused: isPaused)
        }
        .clipShape(RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        }
        .padding(.horizontal)
        .opacity(cardReveal)
        .offset(y: (1 - cardReveal) * 22)
        .scaleEffect(0.96 + 0.04 * cardReveal, anchor: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHidden(!cardVisible)
        .task(id: morphID) {
            await runEntranceIfNeeded()
        }
        .onChange(of: playEntranceReveal) { wasPlaying, shouldPlay in
            guard shouldPlay, !wasPlaying else { return }
            prepareEntranceReplay()
            Task { await runEntranceIfNeeded() }
        }
        .onAppear { syncBreadcrumbCamera(animated: false) }
        .onChange(of: breadcrumbCoordinates.count) { _, _ in
            // Snap camera — animated Map updates during GPS ticks cause hitching.
            syncBreadcrumbCamera(animated: false)
        }
        .onChange(of: locationService.lastLocation?.coordinate.latitude) { _, _ in
            syncBreadcrumbCamera(animated: false)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: !isPaused && !reduceMotion)
                Text(statusText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .matchedGeometryEffectIfAvailable(
                stringID: RecordingMorphID.statusChip,
                namespace: morphNamespace,
                isSource: true
            )

            Spacer(minLength: 4)

            if !vehicles.isEmpty {
                RecordingVehiclePicker(
                    vehicles: vehicles,
                    selectedVehicleID: recordingService.activeRecordingVehicleID(in: modelContext),
                    onSelect: { recordingService.setRecordingVehicle($0) },
                    compact: true
                )
            }

            GPSQualityBadge(quality: locationService.gpsQuality)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Button {
                if isPaused {
                    recordingService.resumeRecording()
                } else {
                    recordingService.pauseRecording()
                }
            } label: {
                Label(isPaused ? L10n.resume : L10n.pause, systemImage: isPaused ? "play.fill" : "pause.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftPressBorderedButtonStyle(reduceMotion: reduceMotion))
            .controlSize(.small)
            .tint(.white)

            Button(role: .destructive) {
                if let onStop {
                    onStop()
                } else {
                    recordingService.stopManualRecording()
                }
            } label: {
                Text(L10n.stop)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
        }
    }

    @MainActor
    private func prepareEntranceReplay() {
        didRunEntrance = false
        guard !reduceMotion else { return }
        cardReveal = 0
        carDriveIn = 0
        detailsReveal = 0
    }

    @MainActor
    private func settleEntrance() {
        cardReveal = 1
        carDriveIn = 1
        detailsReveal = 1
    }

    @MainActor
    private func runEntranceIfNeeded() async {
        guard playEntranceReveal else {
            if !didRunEntrance {
                settleEntrance()
                didRunEntrance = true
            }
            return
        }
        guard !didRunEntrance else { return }
        didRunEntrance = true

        if reduceMotion {
            settleEntrance()
            onEntranceFinished?()
            return
        }

        // 1) Card rises in
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            cardReveal = 1
        }
        // 2) Car drives onto the road almost immediately
        try? await Task.sleep(for: .milliseconds(30))
        guard !Task.isCancelled else {
            settleEntrance()
            onEntranceFinished?()
            return
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            carDriveIn = 1
        }
        // 3) Map + stats + buttons settle in
        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else {
            settleEntrance()
            onEntranceFinished?()
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            detailsReveal = 1
        }
        try? await Task.sleep(for: .milliseconds(170))
        if Task.isCancelled {
            settleEntrance()
        }
        onEntranceFinished?()
    }

    @ViewBuilder
    private var liveBreadcrumbMap: some View {
        Map(position: $breadcrumbCamera, interactionModes: []) {
            if breadcrumbCoordinates.count >= 2 {
                MapPolyline(coordinates: breadcrumbCoordinates)
                    .stroke(
                        Color.white.opacity(0.85),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
            }

            if let liveDotCoordinate {
                Annotation("", coordinate: liveDotCoordinate) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.28))
                            .frame(width: 16, height: 16)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .disabled(true)
        .accessibilityHidden(true)
    }

    private func syncBreadcrumbCamera(animated: Bool) {
        let path = breadcrumbCoordinates
        let center = liveDotCoordinate ?? path.last
        guard let center else { return }

        var minLat = center.latitude
        var maxLat = center.latitude
        var minLon = center.longitude
        var maxLon = center.longitude
        for coordinate in path.suffix(40) {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.004, (maxLat - minLat) * 1.8),
                longitudeDelta: max(0.004, (maxLon - minLon) * 1.8)
            )
        )

        if animated {
            withAnimation(TrailhoundMotion.gentle) {
                breadcrumbCamera = .region(region)
            }
        } else {
            breadcrumbCamera = .region(region)
        }
    }

    private var statusIcon: String {
        isPaused ? "pause.circle.fill" : "record.circle.fill"
    }

    private var statusColor: Color {
        isPaused ? .yellow : .red
    }

    private var accessibilitySummary: String {
        let format = L10n.string("recording.accessibility.summary")
        return String(format: format, statusText, elapsedText, speedText, distanceText)
    }

    private func statPill(icon: String, label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(text)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .numericTextAnimation(value: text)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(text)")
    }
}

#Preview {
    ActiveTripView(playEntranceReveal: true)
        .environment(PreviewData.shared.recordingService)
        .environment(LocationService())
}
