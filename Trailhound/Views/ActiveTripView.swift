import CoreLocation
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
    @State private var cardAnchorForStop = RecordingCardAnchor()

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

    private var shouldAnimateRoad: Bool {
        !isPaused && cardVisible && isRecordingCardVisible
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
                    isAnimating: shouldAnimateRoad,
                    driveInProgress: carDriveIn
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
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: statusIcon)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)
                    .symbolEffect(
                        .pulse,
                        options: .repeating,
                        isActive: !isPaused && !reduceMotion && isRecordingCardVisible
                    )
                Text(statusText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .modifier(RecordingStatusChipMorphModifier(
                morphNamespace: morphNamespace
            ))

            Spacer(minLength: 4)

            if !vehicles.isEmpty {
                RecordingVehiclePicker(
                    vehicles: vehicles,
                    selectedVehicleID: recordingService.activeRecordingVehicleID(in: modelContext),
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
                Label(isPaused ? L10n.resume : L10n.pause, systemImage: isPaused ? "play.fill" : "pause.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftPressBorderedButtonStyle(reduceMotion: reduceMotion))
            .controlSize(.small)
            .tint(.white)

            Button(role: .destructive) {
                if let onStop {
                    onStop(cardAnchorForStop)
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

    private func updateCardAnchor(_ frame: CGRect) {
        let next = RecordingCardAnchor(
            minX: frame.minX,
            minY: frame.minY,
            width: frame.width
        )
        guard next.width > 0 else { return }
        let previous = cardAnchorForStop
        let moved = abs(next.minY - previous.minY) > 12
            || abs(next.minX - previous.minX) > 12
            || abs(next.width - previous.width) > 2
        if previous.width == 0 || moved {
            cardAnchorForStop = next
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

    private var accessibilitySummary: String {
        let format = L10n.string("recording.accessibility.summary")
        return String(
            format: format,
            statusText,
            DateFormatters.formatDuration(recordingService.displayElapsedTime),
            "\(Int(max(0, recordingService.displaySpeedMps) * 3.6)) \(L10n.speedKmh)",
            DateFormatters.formatDistance(recordingService.displayDistanceMeters)
        )
    }
}

// MARK: - Subviews (isolate observation)

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
        HStack(spacing: 8) {
            if showsAlwaysLocationHint {
                Button {
                    locationService.requestPermission()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "location.circle")
                            .font(.caption2)
                        Text(L10n.string("recording.location.always_required"))
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("recording.location.always_required"))
            }

            GPSQualityBadge(quality: displayedGPSQuality)
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
        let kmh = Int(max(0, recordingService.displaySpeedMps) * 3.6)
        return "\(kmh) \(L10n.speedKmh)"
    }

    private var elapsedText: String {
        DateFormatters.formatDuration(recordingService.displayElapsedTime)
    }

    private var distanceText: String {
        DateFormatters.formatDistance(recordingService.displayDistanceMeters)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statPill(icon: "clock.fill", label: L10n.duration, text: elapsedText)
            statPill(icon: "speedometer", label: L10n.currentSpeed, text: speedText)
            statPill(icon: "location.fill", label: L10n.string("label.distance"), text: distanceText)
        }
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
