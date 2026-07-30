import CoreLocation
import Foundation
import SwiftData
import WidgetKit

enum TripRecordingState: Equatable {
    case idle
    case recording
    case paused

    var isActiveSession: Bool {
        self == .recording || self == .paused
    }
}

@MainActor
@Observable
final class TripRecordingService {
    private(set) var state: TripRecordingState = .idle
    private(set) var currentDistanceMeters: Double = 0
    private(set) var currentSpeedMps: Double = 0
    private(set) var recordingStartedAt: Date?
    private(set) var elapsedTime: TimeInterval = 0
    /// Live breadcrumb path for the active session (updates as points are recorded).
    private(set) var liveBreadcrumbCoordinates: [CLLocationCoordinate2D] = []
    /// Breadcrumb polylines split at GPS gaps (no straight chords over missing data).
    private(set) var liveBreadcrumbSegments: [[CLLocationCoordinate2D]] = []

    /// Throttled snapshots for on-screen recording UI (see `RecordingDisplaySampler`).
    private(set) var displayElapsedTime: TimeInterval = 0
    private(set) var displayDistanceMeters: Double = 0
    private(set) var displaySpeedMps: Double = 0

    var activeTripID: UUID? { activeTrip?.id }

    private let locationService: LocationService
    private let settings: AppSettings
    private var displaySampler = RecordingDisplaySampler()

    private var modelContext: ModelContext?
    private var modelContainer: ModelContainer?
    private var activeTrip: Trip?
    private var lastRecordedLocation: CLLocation?
    private var pointSequence = 0
    private var pointsSinceLastSave = 0
    private let saveBatchSize = 10
    private var elapsedTimer: Timer?
    @ObservationIgnored nonisolated(unsafe) private var elapsedTimerTarget: ElapsedTimerTarget?
    private var maxSpeedMps: Double = 0
    /// Last speed that passed every trust gate, so the next one can be checked for a physically
    /// impossible jump.
    private var lastTrustedSpeedMps: Double?
    private var currentStopStartedAt: Date?
    private var currentStopCoordinate: CLLocationCoordinate2D?

    private var stopSpeedMps: Double {
        RecordingConfiguration.stopDetectionSpeedKmh / 3.6
    }

    private static weak var elapsedTimerService: TripRecordingService?

    init(
        locationService: LocationService,
        settings: AppSettings = .shared
    ) {
        self.locationService = locationService
        self.settings = settings

        locationService.onLocationUpdate = { [weak self] location in
            Task { @MainActor in
                self?.handleLocationUpdate(location)
            }
        }
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.modelContainer = modelContext.container
    }

    /// Persists the vehicle for new trips, marks it default in Pairing, and updates the active trip if recording.
    func setRecordingVehicle(_ vehicleID: UUID) {
        guard let modelContext else { return }
        guard let vehicle = VehicleResolver.vehicle(withID: vehicleID, in: modelContext) else { return }

        settings.recordingVehicleID = vehicleID
        VehiclePairingService.setDefaultVehicle(vehicle, in: modelContext)

        if let trip = activeTrip {
            VehicleResolver.assign(vehicle: vehicle, to: trip)
            try? modelContext.save()
        }
    }

    func activeRecordingVehicleID(in context: ModelContext) -> UUID? {
        if let trip = activeTrip, let id = trip.vehicleID {
            return id
        }
        return VehicleResolver.resolveActiveVehicle(in: context, settings: settings)?.id
    }

    /// For views that already hold a `@Query` vehicle list — avoids a store fetch per body pass.
    func activeRecordingVehicleID(from vehicles: [VehicleProfile]) -> UUID? {
        if let trip = activeTrip, let id = trip.vehicleID {
            return id
        }
        return VehicleResolver.resolveActiveVehicle(from: vehicles, settings: settings)?.id
    }

    func stopIdleServices() {
        locationService.stopTracking()
        stopElapsedTimer()
    }

    @discardableResult
    func startManualRecording() -> Bool {
        guard state == .idle else { return false }
        DevLog.shared.log(.recording, "startManualRecording")
        beginRecording(trigger: .manual)
        return state == .recording
    }

    func stopManualRecording() {
        DevLog.shared.log(.recording, "stopManualRecording (state=\(state))")
        settings.pendingStopRecordingRequest = false
        switch state {
        case .recording, .paused:
            stopRecording(saveTrip: true)
        case .idle:
            break
        }
    }

    func processExternalStartRequest() {
        DevLog.shared.log(.recording, "processExternalStartRequest (state: \(state))")
        guard state == .idle else {
            settings.pendingStartRecordingRequest = false
            settings.awaitingExternalStartConfirmation = false
            return
        }

        settings.pendingStopRecordingRequest = false
        settings.pendingPauseRecordingRequest = false
        settings.pendingResumeRecordingRequest = false

        if settings.confirmExternalRecordingStart {
            settings.awaitingExternalStartConfirmation = true
            settings.pendingStartRecordingRequest = false
            return
        }

        if startManualRecording() {
            settings.pendingStartRecordingRequest = false
        }
    }

    func confirmExternalStartRecording() {
        settings.awaitingExternalStartConfirmation = false
        _ = startManualRecording()
    }

    func cancelExternalStartRecording() {
        settings.awaitingExternalStartConfirmation = false
        settings.pendingStartRecordingRequest = false
    }

    func processExternalStopRequest() {
        DevLog.shared.log(.recording, "processExternalStopRequest (state: \(state))")
        settings.pendingStopRecordingRequest = false
        guard state.isActiveSession else { return }
        stopRecording(saveTrip: true)
    }

    func processExternalPauseRequest() {
        settings.pendingPauseRecordingRequest = false
        if state == .recording {
            pauseRecording()
        } else if state == .paused {
            syncExternalState(force: true)
        }
    }

    func processExternalResumeRequest() {
        settings.pendingResumeRecordingRequest = false
        if state == .paused {
            resumeRecording()
        } else if state == .recording {
            syncExternalState(force: true)
        }
    }

    func pauseRecording() {
        guard state == .recording else { return }
        updateElapsedTime()
        state = .paused
        RecordingDiagnostics.logPaused(tripID: activeTrip?.id)
        stopElapsedTimer()
        syncExternalState(force: true)
        TrailhoundHaptics.recordingPaused()
    }

    func resumeRecording() {
        guard state == .paused else { return }
        recordingStartedAt = Date().addingTimeInterval(-elapsedTime)
        state = .recording
        RecordingDiagnostics.logResumed(tripID: activeTrip?.id, orphanResume: false)
        startElapsedTimer()
        syncExternalState(force: true)
        TrailhoundHaptics.recordingResumed()
    }

    func resumeRecording(trip: Trip) {
        guard state == .idle, modelContext != nil else { return }

        activeTrip = trip
        state = .recording
        recordingStartedAt = trip.startedAt
        currentDistanceMeters = trip.distanceMeters
        pointSequence = (trip.sortedPoints.last?.sequence ?? -1) + 1
        currentSpeedMps = 0
        elapsedTime = Date().timeIntervalSince(trip.startedAt)
        // A trip saved before speeds were vetted may carry a phantom maximum, so do not let
        // resuming it write that value back.
        maxSpeedMps = trip.maxSpeedMps.flatMap {
            RecordingMovementPolicy.isRecordableSpeed($0) ? $0 : nil
        } ?? 0
        lastTrustedSpeedMps = trip.sortedPoints.last?.speedMps
        lastRecordedLocation = trip.sortedPoints.last?.location
        liveBreadcrumbCoordinates = trip.coordinates
        liveBreadcrumbSegments = Self.breadcrumbSegments(from: trip.sortedPoints)
        refreshDisplaySnapshot(force: true)
        currentStopStartedAt = nil
        currentStopCoordinate = nil
        pointsSinceLastSave = 0

        locationService.requestPermission()
        locationService.startTracking()
        if !locationService.canRecordInBackground {
            DevLog.shared.warning(
                .recording,
                "resume orphan \(trip.id.uuidString.prefix(8)): background GPS not active"
            )
        }
        RecordingDiagnostics.logResumed(tripID: trip.id, orphanResume: true)
        startElapsedTimer()
        if !UITestSupport.isUnitTesting {
            RecordingLiveActivityService.start(
                startedAt: trip.startedAt,
                elapsed: elapsedTime,
                distanceMeters: currentDistanceMeters
            )
        }
        syncExternalState(force: true)
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        guard state == .recording else {
            if state == .paused {
                RecordingDiagnostics.logIncomingFix(
                    tripID: activeTrip?.id,
                    location: location,
                    state: state
                )
            }
            return
        }
        processRecordingLocationUpdate(location)
    }

    private func processRecordingLocationUpdate(_ location: CLLocation) {
        RecordingDiagnostics.logIncomingFix(tripID: activeTrip?.id, location: location, state: state)
        updateElapsedTime()

        let speed = location.speed >= 0 ? location.speed : 0
        currentSpeedMps = speed

        if speed < stopSpeedMps {
            if currentStopStartedAt == nil {
                currentStopStartedAt = Date()
                currentStopCoordinate = location.coordinate
            }
        } else {
            finalizeStopIfNeeded()
        }

        applyDistanceSample(from: location, speed: speed)
        refreshDisplaySnapshot()
        syncExternalState()
    }

    /// Core Location's speed for this fix, or nil when the fix is too uncertain, too old or too
    /// fast to be believed. The position is kept either way — dropping points is what makes routes
    /// look broken, and only the speedometer is at stake here.
    private func trustedGPSSpeed(for location: CLLocation) -> Double? {
        let age = Date().timeIntervalSince(location.timestamp)
        let trusted = RecordingMovementPolicy.trustedGPSSpeedMps(
            reportedMps: location.speed,
            speedAccuracyMps: location.speedAccuracy,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            fixAgeSeconds: age
        )

        // A speed of -1 just means Core Location has no reading yet; that is normal and not
        // worth a log line.
        if trusted == nil, location.speed >= 0,
           let reason = RecordingMovementPolicy.speedRejectionReason(
               reportedMps: location.speed,
               speedAccuracyMps: location.speedAccuracy,
               horizontalAccuracyMeters: location.horizontalAccuracy,
               fixAgeSeconds: age
           ) {
            RecordingDiagnostics.logSpeedRejected(
                tripID: activeTrip?.id,
                reason: reason,
                reportedKmh: location.speed * 3.6,
                speedAccuracyMps: location.speedAccuracy,
                accuracyMeters: location.horizontalAccuracy,
                ageSeconds: age
            )
        }
        return trusted
    }

    /// What to write on a point: Core Location's speed when it passed every gate, otherwise the
    /// speed the covered distance implies. Nil when neither survives.
    private func speedToStore(
        for location: CLLocation,
        delta: CLLocationDistance,
        timeDelta: TimeInterval
    ) -> Double? {
        if let trusted = trustedGPSSpeed(for: location),
           RecordingMovementPolicy.isPlausibleAcceleration(
               from: lastTrustedSpeedMps,
               to: trusted,
               timeDelta: timeDelta
           ) {
            return trusted
        }

        let implied = delta / max(0.01, timeDelta)
        guard RecordingMovementPolicy.isRecordableSpeed(implied),
              RecordingMovementPolicy.isPlausibleAcceleration(
                  from: lastTrustedSpeedMps,
                  to: implied,
                  timeDelta: timeDelta
              ) else { return nil }
        return implied
    }

    /// The trip's maximum is now always one of its point speeds, so it can never exceed what the
    /// route itself shows — the 203 km/h phantom came from a value no point ever carried.
    private func noteStoredSpeed(_ speedMps: Double?) {
        guard let speedMps, RecordingMovementPolicy.isRecordableSpeed(speedMps) else { return }
        lastTrustedSpeedMps = speedMps
        maxSpeedMps = max(maxSpeedMps, speedMps)
    }

    private func applyDistanceSample(from location: CLLocation, speed: Double, forcePoint: Bool = false) {
        if let previous = lastRecordedLocation {
            let delta = location.distance(from: previous)
            let timeDelta = max(0.01, location.timestamp.timeIntervalSince(previous.timestamp))
            let decision = RecordingMovementPolicy.decision(
                delta: delta,
                timeDelta: timeDelta,
                speed: speed
            )

            switch decision {
            case .ignore:
                RecordingDiagnostics.logMovement(
                    tripID: activeTrip?.id,
                    decision: .ignore,
                    delta: delta,
                    timeDelta: timeDelta,
                    accuracy: location.horizontalAccuracy,
                    locationSpeedKmh: speed * 3.6,
                    storedSpeedKmh: nil,
                    distanceMeters: currentDistanceMeters,
                    pointSequence: pointSequence,
                    mapNewSegment: false,
                    ignoreReason: RecordingMovementPolicy.ignoreReason(
                        delta: delta,
                        timeDelta: timeDelta,
                        locationSpeedMps: speed
                    )
                )
                return
            case .accumulate:
                currentDistanceMeters += delta
                lastRecordedLocation = location
                activeTrip?.distanceMeters = currentDistanceMeters
                let storedSpeed = speedToStore(for: location, delta: delta, timeDelta: timeDelta)
                noteStoredSpeed(storedSpeed)
                RecordingDiagnostics.logMovement(
                    tripID: activeTrip?.id,
                    decision: .accumulate,
                    delta: delta,
                    timeDelta: timeDelta,
                    accuracy: location.horizontalAccuracy,
                    locationSpeedKmh: speed * 3.6,
                    storedSpeedKmh: storedSpeed.map { $0 * 3.6 },
                    distanceMeters: currentDistanceMeters,
                    pointSequence: pointSequence,
                    mapNewSegment: false
                )
                appendPoint(
                    from: location,
                    speed: storedSpeed,
                    startsNewMapSegment: false
                )
            case .gapResume:
                lastRecordedLocation = location
                activeTrip?.distanceMeters = currentDistanceMeters
                // The jump itself is signal loss, so nothing about it can imply a speed. Only
                // Core Location's own reading, if it passes the gates, applies here.
                let storedSpeed = trustedGPSSpeed(for: location)
                noteStoredSpeed(storedSpeed)
                RecordingDiagnostics.logMovement(
                    tripID: activeTrip?.id,
                    decision: .gapResume,
                    delta: delta,
                    timeDelta: timeDelta,
                    accuracy: location.horizontalAccuracy,
                    locationSpeedKmh: speed * 3.6,
                    storedSpeedKmh: storedSpeed.map { $0 * 3.6 },
                    distanceMeters: currentDistanceMeters,
                    pointSequence: pointSequence,
                    mapNewSegment: true
                )
                appendPoint(
                    from: location,
                    speed: storedSpeed,
                    startsNewMapSegment: true
                )
            }
        } else {
            // No previous fix, so nothing to cross-check against: Core Location's own reading is
            // the only candidate, and on a cold start that is exactly the one that used to hand
            // the trip a 203 km/h record it never reached.
            let storedSpeed = trustedGPSSpeed(for: location)
            noteStoredSpeed(storedSpeed)
            RecordingDiagnostics.logMovement(
                tripID: activeTrip?.id,
                decision: .accumulate,
                delta: 0,
                timeDelta: 0,
                accuracy: location.horizontalAccuracy,
                locationSpeedKmh: speed * 3.6,
                storedSpeedKmh: storedSpeed.map { $0 * 3.6 },
                distanceMeters: currentDistanceMeters,
                pointSequence: pointSequence,
                mapNewSegment: false,
                ignoreReason: "first_fix"
            )
            lastRecordedLocation = location
            appendPoint(from: location, speed: storedSpeed, startsNewMapSegment: false)
        }
    }

    private func finalizeRecordingLocation() {
        guard state == .recording || state == .paused else { return }
        guard let location = locationService.lastLocation else { return }

        let speed = location.speed >= 0 ? location.speed : currentSpeedMps
        applyDistanceSample(from: location, speed: speed, forcePoint: true)
        reconcileTripDistance()
    }

    private func reconcileTripDistance() {
        guard let trip = activeTrip else { return }

        let points = trip.sortedPoints
        var computed: Double = 0
        if points.count > 1 {
            for index in 1..<points.count {
                let previous = points[index - 1].location
                let current = points[index].location
                let delta = current.distance(from: previous)
                let timeDelta = max(0.01, current.timestamp.timeIntervalSince(previous.timestamp))
                let speed = points[index].speedMps
                    ?? (current.speed >= 0 ? current.speed : 0)
                if RecordingMovementPolicy.decision(delta: delta, timeDelta: timeDelta, speed: speed) == .accumulate {
                    computed += delta
                }
            }
        }

        if let lastPoint = points.last?.location, let lastRecordedLocation {
            let tail = lastRecordedLocation.distance(from: lastPoint)
            let timeDelta = max(
                0.01,
                lastRecordedLocation.timestamp.timeIntervalSince(lastPoint.timestamp)
            )
            let speed = lastRecordedLocation.speed >= 0 ? lastRecordedLocation.speed : 0
            if RecordingMovementPolicy.decision(delta: tail, timeDelta: timeDelta, speed: speed) == .accumulate {
                computed += tail
            }
        }

        currentDistanceMeters = max(currentDistanceMeters, computed)
        trip.distanceMeters = currentDistanceMeters
        RecordingDiagnostics.logReconcile(
            tripID: trip.id,
            liveMeters: currentDistanceMeters,
            fromPointsMeters: computed
        )
    }

    private func finalizeStopIfNeeded() {
        guard let trip = activeTrip,
              let modelContext,
              let startedAt = currentStopStartedAt,
              let coordinate = currentStopCoordinate else { return }

        let duration = Date().timeIntervalSince(startedAt)
        guard duration >= RecordingConfiguration.minimumParkingStopDurationSeconds else {
            currentStopStartedAt = nil
            currentStopCoordinate = nil
            return
        }

        let stop = TripStop(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            startedAt: startedAt,
            durationSeconds: duration,
            trip: trip
        )
        trip.stops.append(stop)
        modelContext.insert(stop)
        currentStopStartedAt = nil
        currentStopCoordinate = nil
    }

    private func beginRecording(trigger: RecordingTrigger) {
        guard state == .idle else { return }
        beginRecordingImmediately()
    }

    private func beginRecordingImmediately(
        startedAt: Date? = nil,
        announceStart: Bool = true,
        processInitialLocation: Bool = true
    ) {
        guard state == .idle else { return }
        guard let modelContext else { return }

        let resolvedStartedAt = startedAt ?? Date()
        state = .recording
        currentDistanceMeters = 0
        currentSpeedMps = 0
        lastRecordedLocation = nil
        pointSequence = 0
        pointsSinceLastSave = 0
        recordingStartedAt = resolvedStartedAt
        elapsedTime = Date().timeIntervalSince(resolvedStartedAt)
        maxSpeedMps = 0
        lastTrustedSpeedMps = nil
        currentStopStartedAt = nil
        currentStopCoordinate = nil
        liveBreadcrumbCoordinates = []
        liveBreadcrumbSegments = []
        resetDisplaySnapshot()

        let trip = Trip(startedAt: resolvedStartedAt)
        if let vehicle = VehicleResolver.resolveActiveVehicle(in: modelContext, settings: settings) {
            VehicleResolver.assign(vehicle: vehicle, to: trip)
            settings.recordingVehicleID = vehicle.id
        }
        modelContext.insert(trip)
        do {
            try modelContext.save()
        } catch {
            AppErrorPresenter.shared.present(error.localizedDescription)
            resetActiveSession()
            state = .idle
            return
        }
        activeTrip = trip
        DevLog.shared.log(.recording, "Trip started: id=\(trip.id)")

        locationService.requestPermission()
        locationService.startTracking()
        RecordingDiagnostics.beginSession(
            tripID: trip.id,
            authorization: locationService.authorizationState,
            backgroundUpdatesEnabled: locationService.canRecordInBackground
        )
        if !locationService.canRecordInBackground {
            DevLog.shared.warning(
                .recording,
                "session \(trip.id.uuidString.prefix(8)): Always/background GPS not active — fixes may stop when screen locks"
            )
        }
        startElapsedTimer()
        if !UITestSupport.isUnitTesting {
            RecordingLiveActivityService.start(startedAt: resolvedStartedAt)
            TripNotificationService.notifyTripStarted(tripID: trip.id)
        }
        syncExternalState(force: true)
        if announceStart, !UITestSupport.isUnitTesting {
            TrailhoundHaptics.recordingStarted()
            TrailhoundSounds.recordingStarted()
        }

        if processInitialLocation, !UITestSupport.isUnitTesting,
           let location = locationService.lastLocation {
            processRecordingLocationUpdate(location)
        }
    }

    private enum RecordingTrigger {
        case manual
    }

    private func appendPoint(
        from location: CLLocation,
        speed: Double?,
        startsNewMapSegment: Bool = false
    ) {
        guard let trip = activeTrip, let modelContext else { return }

        let recordedSpeed = speed.flatMap {
            RecordingMovementPolicy.isRecordableSpeed($0) ? $0 : nil
        }

        let point = TripPoint(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            sequence: pointSequence,
            speedMps: recordedSpeed,
            trip: trip
        )
        pointSequence += 1
        trip.points.append(point)
        appendLiveBreadcrumb(location.coordinate, startsNewMapSegment: startsNewMapSegment)
        modelContext.insert(point)
        pointsSinceLastSave += 1
        let willBatchSave = pointsSinceLastSave >= saveBatchSize
        RecordingDiagnostics.logPointPersisted(
            tripID: trip.id,
            sequence: point.sequence,
            batchSave: willBatchSave
        )
        if willBatchSave {
            trip.distanceMeters = currentDistanceMeters
            trip.invalidatePointCaches()
            flushPointsToStore()
        }
    }

    private func appendLiveBreadcrumb(
        _ coordinate: CLLocationCoordinate2D,
        startsNewMapSegment: Bool
    ) {
        liveBreadcrumbCoordinates.append(coordinate)
        if startsNewMapSegment || liveBreadcrumbSegments.isEmpty {
            liveBreadcrumbSegments.append([coordinate])
        } else {
            liveBreadcrumbSegments[liveBreadcrumbSegments.count - 1].append(coordinate)
        }
    }

    private static func breadcrumbSegments(from points: [TripPoint]) -> [[CLLocationCoordinate2D]] {
        guard let first = points.first else { return [] }
        var segments: [[CLLocationCoordinate2D]] = [[first.coordinate]]
        guard points.count > 1 else { return segments }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let delta = current.location.distance(from: previous.location)
            let timeDelta = max(0.01, current.timestamp.timeIntervalSince(previous.timestamp))
            let speed = current.speedMps ?? (current.location.speed >= 0 ? current.location.speed : 0)
            if RecordingMovementPolicy.shouldDrawMapSegment(delta: delta, timeDelta: timeDelta, speed: speed) {
                segments[segments.count - 1].append(current.coordinate)
            } else {
                segments.append([current.coordinate])
            }
        }
        return segments
    }

    private func flushPointsToStore() {
        guard let modelContext else { return }
        do {
            try modelContext.save()
            pointsSinceLastSave = 0
        } catch {
            RecordingDiagnostics.logPersistFailure(tripID: activeTrip?.id, error: error.localizedDescription)
            AppErrorPresenter.shared.present(error.localizedDescription)
        }
    }

    private func stopRecording(saveTrip: Bool) {
        guard state.isActiveSession else { return }
        let tripID = activeTrip?.id
        let pointCountBeforeStop = activeTrip?.points.count ?? 0

        finalizeRecordingLocation()
        finalizeStopIfNeeded()

        let distanceBeforeIdle = currentDistanceMeters
        let elapsed = elapsedTime
        let maxKmh = maxSpeedMps * 3.6
        let reconciled = activeTrip.map { trip in
            var computed: Double = 0
            let points = trip.sortedPoints
            if points.count > 1 {
                for index in 1..<points.count {
                    let previous = points[index - 1].location
                    let current = points[index].location
                    let delta = current.distance(from: previous)
                    let timeDelta = max(0.01, current.timestamp.timeIntervalSince(previous.timestamp))
                    let speed = points[index].speedMps ?? 0
                    if RecordingMovementPolicy.decision(delta: delta, timeDelta: timeDelta, speed: speed) == .accumulate {
                        computed += delta
                    }
                }
            }
            return computed
        }

        DevLog.shared.log(
            .recording,
            "stopRecording: saveTrip=\(saveTrip), distance=\(Int(distanceBeforeIdle))m, elapsed=\(Int(elapsed))s points=\(pointCountBeforeStop)"
        )
        state = .idle
        settings.syncRecordingState(
            isRecording: false,
            isPaused: false,
            elapsed: 0,
            distanceMeters: 0,
            currentSpeedKmh: 0
        )
        if !UITestSupport.isUnitTesting {
            TrailhoundHaptics.recordingStopped()
            TrailhoundSounds.recordingStopped()
        }
        locationService.stopTracking()
        stopElapsedTimer()
        ensureTripHasAnchorPointIfNeeded()
        flushPointsToStore()
        if !UITestSupport.isUnitTesting {
            RecordingLiveActivityService.stop()
        }
        RecordingSyncCoordinator.reset()

        guard let trip = activeTrip, let modelContext else {
            if let tripID {
                RecordingDiagnostics.endSession(
                    tripID: tripID,
                    saved: false,
                    distanceMeters: distanceBeforeIdle,
                    durationSeconds: elapsed,
                    maxSpeedKmh: maxKmh,
                    pointCount: pointCountBeforeStop,
                    reconciledDistanceMeters: reconciled
                )
            }
            resetActiveSession()
            return
        }

        if !UITestSupport.isUnitTesting {
            TripNotificationService.cancelOrphanStaleNotification(tripID: trip.id)
        }

        let endedAt = Date()
        let duration = endedAt.timeIntervalSince(trip.startedAt)
        let shouldSave = saveTrip

        if shouldSave {
            trip.endedAt = endedAt
            trip.distanceMeters = currentDistanceMeters
            trip.maxSpeedMps = maxSpeedMps > 0 ? maxSpeedMps : nil
            let vehicle = trip.vehicleID.flatMap { VehicleResolver.vehicle(withID: $0, in: modelContext) }
            trip.vehicle = nil
            trip.estimatedFuelCost = FuelCostCalculator.estimateCost(
                distanceMeters: currentDistanceMeters,
                vehicle: vehicle
            )
            trip.geocodeStatus = .pending

            TripDerivedMetrics.recomputeEndpoints(for: trip)
            let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
            PlaceMatchingService.matchPlaces(for: trip, places: places)
            let routeSummary = TripListViewModel.routeSummary(
                for: trip,
                places: places,
                privacyRadius: settings.privacyRadiusMeters
            )
            TripDerivedMetrics.recomputeNightDistance(for: trip)
            TripDerivedMetrics.refreshSearchIndex(
                for: trip,
                places: places,
                privacyRadius: settings.privacyRadiusMeters
            )
            TripRollupService.add(trip, in: modelContext)

            do {
                try modelContext.save()
            } catch {
                AppErrorPresenter.shared.present(error.localizedDescription)
                resetActiveSession()
                syncExternalState()
                return
            }
            if !UITestSupport.isUnitTesting {
                TripNotificationService.notifyTripEnded(
                    tripID: trip.id,
                    distanceMeters: currentDistanceMeters,
                    duration: duration,
                    routeSummary: routeSummary
                )
            }

            let tripUUID = trip.id
            let container = modelContainer
            if !UITestSupport.isUnitTesting {
                Task { @MainActor in
                    guard let container else { return }
                    await TripPostProcessor.process(
                        tripUUID: tripUUID,
                        container: container
                    )
                }
            }
        } else {
            if saveTrip, !UITestSupport.isUnitTesting {
                TripNotificationService.notifyTripDiscarded(tripID: trip.id)
            }
            modelContext.delete(trip)
            try? modelContext.save()
        }

        RecordingDiagnostics.endSession(
            tripID: trip.id,
            saved: shouldSave,
            distanceMeters: currentDistanceMeters,
            durationSeconds: duration,
            maxSpeedKmh: maxKmh,
            pointCount: trip.sortedPoints.count,
            reconciledDistanceMeters: reconciled
        )

        resetActiveSession()
        TripStore.syncWidgetWeekDistance(in: modelContext)
        syncExternalState(force: true)
        if !UITestSupport.isUnitTesting {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func ensureTripHasAnchorPointIfNeeded() {
        guard let trip = activeTrip, let modelContext else { return }
        guard trip.points.isEmpty else { return }
        guard let location = locationService.lastLocation else {
            DevLog.shared.warning(.recording, "anchor point skipped \(trip.id.uuidString.prefix(8)): no lastLocation")
            return
        }

        DevLog.shared.log(.recording, "anchor point added \(trip.id.uuidString.prefix(8)) (trip had 0 points)")

        let point = TripPoint(
            timestamp: Date(),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            sequence: pointSequence,
            speedMps: nil,
            trip: trip
        )
        pointSequence += 1
        trip.points.append(point)
        trip.invalidatePointCaches()
        appendLiveBreadcrumb(location.coordinate, startsNewMapSegment: liveBreadcrumbSegments.isEmpty)
        modelContext.insert(point)
        pointsSinceLastSave += 1
    }

    private func resetActiveSession() {
        activeTrip = nil
        lastRecordedLocation = nil
        pointSequence = 0
        pointsSinceLastSave = 0
        currentDistanceMeters = 0
        currentSpeedMps = 0
        recordingStartedAt = nil
        elapsedTime = 0
        maxSpeedMps = 0
        lastTrustedSpeedMps = nil
        currentStopStartedAt = nil
        currentStopCoordinate = nil
        liveBreadcrumbCoordinates = []
        liveBreadcrumbSegments = []
        resetDisplaySnapshot()
    }

    private func resetDisplaySnapshot() {
        displaySampler.reset()
        displayElapsedTime = 0
        displayDistanceMeters = 0
        displaySpeedMps = 0
    }

    private func refreshDisplaySnapshot(force: Bool = false) {
        let now = Date()
        if !force && !displaySampler.shouldPublish(now: now) { return }
        displayElapsedTime = elapsedTime
        displayDistanceMeters = currentDistanceMeters
        displaySpeedMps = currentSpeedMps
    }

    private func syncExternalState(force: Bool = false) {
        guard force || RecordingSyncCoordinator.shouldSync() else { return }

        // Live Activity / widget controls already wrote optimistic App Group
        // state (and may have ended the activity). Don't clobber that while the
        // matching request is still waiting to be applied in-process.
        if settings.pendingStopRecordingRequest {
            settings.syncRecordingState(
                isRecording: false,
                isPaused: false,
                elapsed: elapsedTime,
                distanceMeters: currentDistanceMeters,
                currentSpeedKmh: 0
            )
            return
        }
        if settings.pendingPauseRecordingRequest {
            settings.syncRecordingState(
                isRecording: true,
                isPaused: true,
                elapsed: elapsedTime,
                distanceMeters: currentDistanceMeters,
                currentSpeedKmh: 0
            )
            return
        }
        if settings.pendingResumeRecordingRequest {
            let speedKmh = Int(max(0, currentSpeedMps) * 3.6)
            settings.syncRecordingState(
                isRecording: true,
                isPaused: false,
                elapsed: elapsedTime,
                distanceMeters: currentDistanceMeters,
                currentSpeedKmh: speedKmh
            )
            return
        }

        let speedKmh = Int(max(0, currentSpeedMps) * 3.6)
        let isPaused = state == .paused
        let isRecording = state == .recording
        settings.syncRecordingState(
            isRecording: isRecording || isPaused,
            isPaused: isPaused,
            elapsed: elapsedTime,
            distanceMeters: currentDistanceMeters,
            currentSpeedKmh: speedKmh
        )
        guard !UITestSupport.isUnitTesting else { return }

        if state.isActiveSession, let recordingStartedAt {
            RecordingLiveActivityService.ensureActiveIfNeeded(
                startedAt: recordingStartedAt,
                elapsed: elapsedTime,
                distanceMeters: currentDistanceMeters,
                currentSpeedKmh: speedKmh,
                isPaused: isPaused
            )
        }
        RecordingLiveActivityService.update(
            elapsed: elapsedTime,
            distanceMeters: currentDistanceMeters,
            currentSpeedKmh: speedKmh,
            isPaused: isPaused,
            force: force
        )

        if state.isActiveSession, let tripID = activeTripID {
            AppNotificationStore.shared.syncLiveTripNotification(
                tripID: tripID,
                isPaused: isPaused,
                elapsed: elapsedTime,
                distanceMeters: currentDistanceMeters,
                currentSpeedKmh: speedKmh
            )
        }

        if force {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        Self.elapsedTimerService = self
        let target = ElapsedTimerTarget()
        elapsedTimerTarget = target
        let timer = Timer(timeInterval: 1, target: target, selector: #selector(ElapsedTimerTarget.tick(_:)), userInfo: nil, repeats: true)
        elapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateElapsedTime() {
        guard let startedAt = recordingStartedAt else { return }
        elapsedTime = Date().timeIntervalSince(startedAt)
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        elapsedTimerTarget = nil
        if Self.elapsedTimerService === self {
            Self.elapsedTimerService = nil
        }
    }

    fileprivate func handleElapsedTimerTick() {
        updateElapsedTime()
        refreshDisplaySnapshot()
        syncExternalState()
    }

    static func handleElapsedTimerTickFromBackground() {
        elapsedTimerService?.handleElapsedTimerTick()
    }
}

private nonisolated func dispatchElapsedTimerTickToMainActor() {
    Task { @MainActor in
        TripRecordingService.handleElapsedTimerTickFromBackground()
    }
}

private final class ElapsedTimerTarget: NSObject {
    @objc nonisolated func tick(_ timer: Timer) {
        dispatchElapsedTimerTickToMainActor()
    }
}

@MainActor
enum TripPostProcessor {
    static func process(
        tripUUID: UUID,
        container: ModelContainer
    ) async {
        let context = ModelContext(container)
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        guard let trip = trips.first(where: { $0.id == tripUUID }) else { return }

        // Recorded points are never reduced on disk — display decimation happens in
        // `RouteDisplayPath`. Deleting them here previously destroyed long trips.
        if !UITestSupport.isUnitTesting {
            await enrichTripWithAddresses(
                trip,
                context: context,
                geocodingService: GeocodingService()
            )
        }

        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        PlaceMatchingService.matchPlaces(for: trip, places: places)
        TripDerivedMetrics.recompute(
            for: trip,
            places: places,
            privacyRadius: AppSettings.shared.privacyRadiusMeters
        )
        try? context.save()
    }

    private static func enrichTripWithAddresses(
        _ trip: Trip,
        context: ModelContext,
        geocodingService: GeocodingService
    ) async {
        var success = true

        if let startCoordinate = trip.startCoordinate {
            let startLocation = CLLocation(latitude: startCoordinate.latitude, longitude: startCoordinate.longitude)
            let address = await geocodingService.reverseGeocode(startLocation)
            trip.startAddress = address
            if address == nil { success = false }
        }

        if let endCoordinate = trip.endCoordinate {
            let endLocation = CLLocation(latitude: endCoordinate.latitude, longitude: endCoordinate.longitude)
            let address = await geocodingService.reverseGeocode(endLocation)
            trip.endAddress = address
            if address == nil { success = false }
        }

        trip.geocodeStatus = success ? .complete : .failed
        try? context.save()
    }
}
