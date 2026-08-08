import CoreLocation
import SwiftData
import SwiftUI
import UIKit

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

    /// Mark-only chip: the glyph now fits its frame, so the box grows to keep the same optical size.
    private var avatarSize: CGFloat { compact ? 26 : 28 }

    private var vehiclePhotoPrefetchID: String {
        VehiclePhotoStore.prefetchTaskID(for: vehicles)
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
                        Label(vehicle.name, systemImage: VehicleIconOption.default.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                VehicleAvatarView(
                    systemImage: VehicleIconOption.default.rawValue,
                    photoFileName: selectedVehicle?.photoFileName,
                    size: avatarSize,
                    cornerRadius: avatarSize * 0.28,
                    isElectricAccent: selectedVehicle?.fuelType == .electric,
                    symbolColor: compact ? .white : nil,
                    showsSymbolPlate: false,
                    symbolFitsFrame: true
                )
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(compact ? Color.white.opacity(0.9) : TrailhoundBrandColors.brandBottom)
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 2 : 4)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(L10n.string("recording.vehicle.accessibility"))
        .accessibilityValue(selectedName)
        .task(id: vehiclePhotoPrefetchID) {
            await VehiclePhotoStore.shared.prefetch(vehicles: vehicles)
        }
    }
}

enum RecordingMorphID {
    static let statusChip = "recording.statusChip"
    static let car = "recording.car"
}

/// Pause / Resume / Stop label: glyph matches the title color (never the blue accent tint).
struct RecordingActionLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .white
    /// When false, the glyph swaps instantly (no SF Symbol replace morph).
    var animatedSymbolSwap: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .modifier(RecordingActionSymbolTransition(enabled: animatedSymbolSwap))
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
    }
}

private struct RecordingActionSymbolTransition: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.contentTransition(.symbolEffect(.replace))
        } else {
            content
        }
    }
}

struct ActiveTripView: View {
    var morphNamespace: Namespace.ID?
    var morphID: UUID?
    /// Whole-card fade-in on trip start.
    var playEntranceReveal: Bool = false
    var onEntranceFinished: (() -> Void)?
    var onStop: ((RecordingCardAnchor) -> Void)?
    /// When false, pauses the road animation while another tab is selected.
    var isRecordingCardVisible: Bool = true

    @Environment(TripRecordingService.self) private var recordingService
    @Environment(LocationService.self) private var locationService
    @Environment(\.modelContext) private var modelContext
    @Query private var vehicles: [VehicleProfile]
    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cardReveal: CGFloat = 1
    @State private var carDriveIn: CGFloat = 1
    @State private var detailsReveal: CGFloat = 1
    @State private var didRunEntrance = false
    @State private var anchorBox = RecordingCardAnchorBox()
    /// Decoded thumb for the road scene — injected so TimelineView never hits disk.
    @State private var roadVehiclePhoto: UIImage?

    init(
        morphNamespace: Namespace.ID? = nil,
        morphID: UUID? = nil,
        playEntranceReveal: Bool = false,
        onEntranceFinished: (() -> Void)? = nil,
        onStop: ((RecordingCardAnchor) -> Void)? = nil,
        isRecordingCardVisible: Bool = true
    ) {
        self.morphNamespace = morphNamespace
        self.morphID = morphID
        self.playEntranceReveal = playEntranceReveal
        self.onEntranceFinished = onEntranceFinished
        self.onStop = onStop
        self.isRecordingCardVisible = isRecordingCardVisible
        let settled = !self.playEntranceReveal
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

    /// Keep TimelineView mounted while the card is on-screen (pause freezes the scene, no view swap).
    private var shouldRunRoadClock: Bool {
        cardVisible && isRecordingCardVisible
    }

    private var recordingVehicle: VehicleProfile? {
        let id = recordingService.activeRecordingVehicleID(from: vehicles)
        guard let id else { return nil }
        return vehicles.first(where: { $0.id == id })
    }

    private var roadPhotoIdentity: String {
        let id = recordingVehicle?.id.uuidString ?? "none"
        let file = recordingVehicle?.photoFileName ?? "none"
        // Epoch forces reload when Observation misses nested SwiftData vehicleID mutations.
        return "\(id)|\(file)|\(recordingService.recordingVehicleEpoch)"
    }

    private var vehiclePhotoPrefetchID: String {
        VehiclePhotoStore.prefetchTaskID(for: vehicles)
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
                    isAnimating: shouldRunRoadClock,
                    isPaused: isPaused,
                    driveInProgress: carDriveIn,
                    systemImage: VehicleIconOption.default.rawValue,
                    vehiclePhoto: roadVehiclePhoto,
                    symbolScaleX: -1,
                    allowsVerticalBounce: true
                )
                .matchedGeometryEffectIfAvailable(
                    stringID: RecordingMorphID.car,
                    namespace: morphNamespace,
                    isSource: true
                )
                .matchedGeometryEffectIfAvailable(
                    id: morphID,
                    namespace: morphNamespace,
                    isSource: true
                )
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 72)
            .opacity(detailsReveal)
            .scaleEffect(0.92 + 0.08 * detailsReveal)

            ActiveTripLiveStats()
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
        .background {
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                Color.clear
                    .onAppear { updateCardAnchor(frame) }
                    .onChange(of: frame.origin.y) { _, _ in updateCardAnchor(frame) }
                    .onChange(of: frame.size.width) { _, _ in updateCardAnchor(frame) }
            }
        }
        .accessibilityElement(children: .combine)
        .modifier(RecordingCardAccessibilityLabel(statusText: statusText))
        .accessibilityHidden(!cardVisible)
        .task(id: morphID) {
            await runEntranceIfNeeded()
        }
        .task(id: roadPhotoIdentity) {
            await loadRoadVehiclePhoto()
        }
        .task(id: vehiclePhotoPrefetchID) {
            await VehiclePhotoStore.shared.prefetch(vehicles: vehicles)
        }
        .onChange(of: playEntranceReveal) { wasPlaying, shouldPlay in
            guard shouldPlay, !wasPlaying else { return }
            prepareEntranceReplay()
            Task { await runEntranceIfNeeded() }
        }
    }

    private func loadRoadVehiclePhoto() async {
        let fileName = recordingVehicle?.photoFileName
        guard let fileName, !fileName.isEmpty else {
            roadVehiclePhoto = nil
            return
        }
        let image: UIImage?
        if let synced = VehiclePhotoStore.shared.imageSync(fileName: fileName) {
            image = synced
        } else {
            image = await VehiclePhotoStore.shared.image(fileName: fileName)
        }
        guard recordingVehicle?.photoFileName == fileName else { return }
        // Same asset as RecordingVehiclePicker — no backdrop punch (that eats light vehicles).
        roadVehiclePhoto = image
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: statusIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .symbolEffect(
                        .pulse,
                        options: .repeating,
                        isActive: !isPaused && !reduceMotion && isRecordingCardVisible
                    )
                Text(statusText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .layoutPriority(1)
            .modifier(RecordingStatusChipMorphModifier(
                morphNamespace: morphNamespace
            ))

            Spacer(minLength: 4)

            if !vehicles.isEmpty {
                RecordingVehiclePicker(
                    vehicles: vehicles,
                    selectedVehicleID: recordingService.activeRecordingVehicleID(from: vehicles),
                    onSelect: { recordingService.setRecordingVehicle($0) },
                    compact: true
                )
            }

            RecordingLocationChromeRow()
        }
    }

    private var statusText: String {
        isPaused ? L10n.recordingPaused : L10n.recordingStarted
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
                RecordingActionLabel(
                    title: isPaused ? L10n.resume : L10n.pause,
                    systemImage: isPaused ? "play.fill" : "pause.fill"
                )
            }
            .buttonStyle(SoftPressBorderedButtonStyle(reduceMotion: reduceMotion))
            .controlSize(.small)
            .tint(.white)

            Button(role: .destructive) {
                if let onStop {
                    onStop(anchorBox.value)
                } else {
                    recordingService.stopManualRecording()
                }
            } label: {
                RecordingActionLabel(title: L10n.stop, systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
        }
    }

    /// Writing to the box costs nothing and never invalidates the view, so no threshold is
    /// needed — Stop now sees the card's exact current frame.
    private func updateCardAnchor(_ frame: CGRect) {
        guard frame.width > 0 else { return }
        anchorBox.value = RecordingCardAnchor(
            minX: frame.minX,
            minY: frame.minY,
            width: frame.width
        )
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

        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            cardReveal = 1
        }
        try? await Task.sleep(for: .milliseconds(30))
        guard !Task.isCancelled else {
            settleEntrance()
            onEntranceFinished?()
            return
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            carDriveIn = 1
        }
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

    private var statusIcon: String {
        isPaused ? "pause.circle.fill" : "record.circle.fill"
    }

    private var statusColor: Color {
        isPaused ? .yellow : .red
    }
}

// MARK: - Subviews (isolate observation)

/// The combined label needs the live counters, but reading them in the card's body made the
/// entire card track the display sampler. A modifier has its own body, so the dependency
/// stays here.
private struct RecordingCardAccessibilityLabel: ViewModifier {
    let statusText: String

    @Environment(TripRecordingService.self) private var recordingService

    func body(content: Content) -> some View {
        content.accessibilityLabel(
            RecordingAccessibility.summary(
                status: statusText,
                elapsed: recordingService.displayElapsedTime,
                speedMps: recordingService.displaySpeedMps,
                distanceMeters: recordingService.displayDistanceMeters
            )
        )
    }
}

private struct RecordingStatusChipMorphModifier: ViewModifier {
    var morphNamespace: Namespace.ID?

    func body(content: Content) -> some View {
        content.matchedGeometryEffectIfAvailable(
            stringID: RecordingMorphID.statusChip,
            namespace: morphNamespace,
            isSource: true
        )
    }
}

/// GPS / permission chrome — throttled so location fixes don't rebuild the whole card.
private struct RecordingLocationChromeRow: View {
    @Environment(LocationService.self) private var locationService
    @State private var displayedGPSQuality: LocationService.GPSQuality = .lost
    @State private var showsAlwaysLocationHint = false

    var body: some View {
        HStack(spacing: 4) {
            if showsAlwaysLocationHint {
                Button {
                    locationService.requestPermission()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "location.circle")
                            .font(.system(size: 9, weight: .semibold))
                        Text(L10n.string("recording.location.always_required"))
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("recording.location.always_required"))
            }

            GPSQualityBadge(quality: displayedGPSQuality, compact: true)
        }
        .onAppear {
            refreshFromLocationService()
        }
        .task {
            while !Task.isCancelled {
                refreshFromLocationService()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refreshFromLocationService() {
        let quality = locationService.gpsQuality
        if quality != displayedGPSQuality {
            displayedGPSQuality = quality
        }
        let needsHint = !locationService.canRecordInBackground
        if needsHint != showsAlwaysLocationHint {
            showsAlwaysLocationHint = needsHint
        }
    }
}

/// Live duration / speed / distance — only this subtree tracks display sampler (~4 Hz).
private struct ActiveTripLiveStats: View {
    @Environment(TripRecordingService.self) private var recordingService

    private var speedText: String {
        RecordingAccessibility.speedText(speedMps: recordingService.displaySpeedMps)
    }

    private var elapsedText: String {
        DateFormatters.formatDuration(recordingService.displayElapsedTime)
    }

    private var distanceText: String {
        DateFormatters.formatDistance(recordingService.displayDistanceMeters)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            statPill(icon: "clock.fill", label: L10n.duration, text: elapsedText)
            statPill(icon: "speedometer", label: L10n.currentSpeed, text: speedText)
            statPill(icon: "location.fill", label: L10n.string("label.distance"), text: distanceText)
        }
    }

    private func statPill(icon: String, label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .foregroundStyle(.white.opacity(0.75))
            Text(text)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .numericTextAnimation(value: text)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
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
