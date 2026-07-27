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

    var activeTripID: UUID? { activeTrip?.id }

    private let locationService: LocationService
    private let settings: AppSettings

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
    private var currentStopStartedAt: Date?
    private var currentStopCoordinate: CLLocationCoordinate2D?

    private let minimumDistanceSampleMeters: CLLocationDistance = 2
    private let minimumPointSpacingMeters: CLLocationDistance = 8
    private let maximumPlausibleSegmentMeters: CLLocationDistance = 250
    private let stationarySpeedMps: Double = 0.5
    private let stationaryDistanceMeters: CLLocationDistance = 5

    private var stopSpeedMps: Double {
        settings.stopSpeedKmh / 3.6
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
        stopElapsedTimer()
        syncExternalState(force: true)
        TrailhoundHaptics.recordingPaused()
    }

    func resumeRecording() {
        guard state == .paused else { return }
        recordingStartedAt = Date().addingTimeInterval(-elapsedTime)
        state = .recording
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
        maxSpeedMps = trip.maxSpeedMps ?? 0
        lastRecordedLocation = trip.sortedPoints.last?.location
        liveBreadcrumbCoordinates = trip.coordinates
        currentStopStartedAt = nil
        currentStopCoordinate = nil
        pointsSinceLastSave = 0

        locationService.requestPermission()
        locationService.startTracking()
        startElapsedTimer()
        RecordingLiveActivityService.start(
            startedAt: trip.startedAt,
            elapsed: elapsedTime,
            distanceMeters: currentDistanceMeters
        )
        syncExternalState(force: true)
    }

    private func handleLocationUpdate(_ location: CLLocation) {
        guard state == .recording else { return }
        processRecordingLocationUpdate(location)
    }

    private func processRecordingLocationUpdate(_ location: CLLocation) {
        updateElapsedTime()

        let speed = location.speed >= 0 ? location.speed : 0
        currentSpeedMps = speed
        if speed > maxSpeedMps { maxSpeedMps = speed }

        if speed < stopSpeedMps {
            if currentStopStartedAt == nil {
                currentStopStartedAt = Date()
                currentStopCoordinate = location.coordinate
            }
        } else {
            finalizeStopIfNeeded()
        }

        applyDistanceSample(from: location, speed: speed)
        syncExternalState()
    }

    private func applyDistanceSample(from location: CLLocation, speed: Double, forcePoint: Bool = false) {
        if let previous = lastRecordedLocation {
            let delta = location.distance(from: previous)
            let timeDelta = max(0.01, location.timestamp.timeIntervalSince(previous.timestamp))
            guard shouldAccumulateDistance(delta: delta, speed: speed) else { return }
            guard isPlausibleMovement(delta: delta, timeDelta: timeDelta) else { return }

            currentDistanceMeters += delta
            lastRecordedLocation = location
            activeTrip?.distanceMeters = currentDistanceMeters

            if forcePoint || shouldRecordPoint(delta: delta, timeDelta: timeDelta) {
                appendPoint(from: location, speed: speed)
            }
        } else {
            lastRecordedLocation = location
            appendPoint(from: location, speed: speed)
        }
    }

    private func shouldAccumulateDistance(delta: CLLocationDistance, speed: Double) -> Bool {
        guard delta >= minimumDistanceSampleMeters else { return false }
        if speed < stationarySpeedMps, delta < stationaryDistanceMeters { return false }
        return true
    }

    private func isPlausibleMovement(delta: CLLocationDistance, timeDelta: TimeInterval) -> Bool {
        guard delta <= maximumPlausibleSegmentMeters else { return false }
        let impliedSpeedMps = delta / timeDelta
        return impliedSpeedMps <= 70
    }

    private func shouldRecordPoint(delta: CLLocationDistance, timeDelta: TimeInterval) -> Bool {
        delta >= minimumPointSpacingMeters || timeDelta >= 20
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

        let locations = trip.sortedPoints.map(\.location)
        var computed = DistanceCalculator.totalDistance(for: locations)

        if let lastPoint = locations.last, let lastRecordedLocation {
            let tail = lastRecordedLocation.distance(from: lastPoint)
            if tail >= minimumDistanceSampleMeters, tail <= maximumPlausibleSegmentMeters {
                computed += tail
            }
        }

        currentDistanceMeters = max(currentDistanceMeters, computed)
        trip.distanceMeters = currentDistanceMeters
    }

    private func finalizeStopIfNeeded() {
        guard let trip = activeTrip,
              let modelContext,
              let startedAt = currentStopStartedAt,
              let coordinate = currentStopCoordinate else { return }

        let duration = Date().timeIntervalSince(startedAt)
        guard duration >= settings.tripStopMinimumDurationSeconds else {
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
        currentStopStartedAt = nil
        currentStopCoordinate = nil
        liveBreadcrumbCoordinates = []

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
        startElapsedTimer()
        RecordingLiveActivityService.start(startedAt: resolvedStartedAt)
        TripNotificationService.notifyTripStarted(tripID: trip.id)
        syncExternalState(force: true)
        if announceStart {
            TrailhoundHaptics.recordingStarted()
            TrailhoundSounds.recordingStarted()
        }

        if processInitialLocation, let location = locationService.lastLocation {
            processRecordingLocationUpdate(location)
        }
    }

    private enum RecordingTrigger {
        case manual
    }

    private func appendPoint(from location: CLLocation, speed: Double) {
        guard let trip = activeTrip, let modelContext else { return }

        let point = TripPoint(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            sequence: pointSequence,
            speedMps: speed > 0 ? speed : nil,
            trip: trip
        )
        pointSequence += 1
        trip.points.append(point)
        trip.distanceMeters = currentDistanceMeters
        trip.invalidatePointCaches()
        liveBreadcrumbCoordinates.append(location.coordinate)
        modelContext.insert(point)
        pointsSinceLastSave += 1
        if pointsSinceLastSave >= saveBatchSize {
            flushPointsToStore()
        }
    }

    private func flushPointsToStore() {
        guard let modelContext else { return }
        do {
            try modelContext.save()
            pointsSinceLastSave = 0
        } catch {
            AppErrorPresenter.shared.present(error.localizedDescription)
        }
    }

    private func stopRecording(saveTrip: Bool) {
        guard state.isActiveSession else { return }
        DevLog.shared.log(
            .recording,
            "stopRecording: saveTrip=\(saveTrip), distance=\(Int(currentDistanceMeters))m, elapsed=\(Int(elapsedTime))s"
        )

        finalizeRecordingLocation()
        finalizeStopIfNeeded()
        state = .idle
        settings.syncRecordingState(
            isRecording: false,
            isPaused: false,
            elapsed: 0,
            distanceMeters: 0,
            currentSpeedKmh: 0
        )
        TrailhoundHaptics.recordingStopped()
        TrailhoundSounds.recordingStopped()
        locationService.stopTracking()
        stopElapsedTimer()
        ensureTripHasAnchorPointIfNeeded()
        flushPointsToStore()
        RecordingLiveActivityService.stop()
        RecordingSyncCoordinator.reset()

        guard let trip = activeTrip, let modelContext else {
            resetActiveSession()
            return
        }

        TripNotificationService.cancelOrphanStaleNotification(tripID: trip.id)

        let endedAt = Date()
        let duration = endedAt.timeIntervalSince(trip.startedAt)
        let shouldSave = RecordingStopPolicy.shouldSaveTrip(
            saveTrip: saveTrip,
            reason: .manual,
            duration: duration,
            distanceMeters: currentDistanceMeters,
            minimumDurationSeconds: settings.stopMinimumDurationSeconds,
            minimumDistanceMeters: settings.stopMinimumDistanceMeters
        )

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

            let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
            PlaceMatchingService.matchPlaces(for: trip, places: places)
            let routeSummary = TripListViewModel.routeSummary(
                for: trip,
                places: places,
                privacyRadius: settings.privacyRadiusMeters
            )

            do {
                try modelContext.save()
            } catch {
                AppErrorPresenter.shared.present(error.localizedDescription)
                resetActiveSession()
                syncExternalState()
                return
            }
            TripNotificationService.notifyTripEnded(
                tripID: trip.id,
                distanceMeters: currentDistanceMeters,
                duration: duration,
                routeSummary: routeSummary
            )

            let tripUUID = trip.id
            let container = modelContainer
            Task { @MainActor in
                guard let container else { return }
                await TripPostProcessor.process(
                    tripUUID: tripUUID,
                    container: container
                )
            }
        } else {
            if saveTrip {
                TripNotificationService.notifyTripDiscarded(tripID: trip.id)
            }
            modelContext.delete(trip)
            try? modelContext.save()
        }

        resetActiveSession()
        TripStore.syncWidgetWeekDistance(in: modelContext)
        syncExternalState(force: true)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func ensureTripHasAnchorPointIfNeeded() {
        guard let trip = activeTrip, let modelContext else { return }
        guard trip.points.isEmpty else { return }
        guard let location = locationService.lastLocation else { return }

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
        liveBreadcrumbCoordinates.append(location.coordinate)
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
        currentStopStartedAt = nil
        currentStopCoordinate = nil
        liveBreadcrumbCoordinates = []
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
        let geocodingService = GeocodingService()

        await enrichTripWithAddresses(trip, context: context, geocodingService: geocodingService)
        simplifyStoredPointsIfNeeded(for: trip, context: context)

        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        PlaceMatchingService.matchPlaces(for: trip, places: places)
        try? context.save()
    }

    private static func simplifyStoredPointsIfNeeded(for trip: Trip, context: ModelContext) {
        guard trip.points.count > 1000 else { return }

        let sorted = trip.sortedPoints
        let simplified = DistanceCalculator.simplify(coordinates: sorted.map(\.coordinate))
        guard simplified.count < sorted.count else { return }

        for point in trip.points { context.delete(point) }
        trip.points.removeAll()

        for (index, coordinate) in simplified.enumerated() {
            let source = nearestSourcePoint(to: coordinate, in: sorted)
            let point = TripPoint(
                timestamp: source?.timestamp ?? trip.startedAt.addingTimeInterval(TimeInterval(index)),
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                sequence: index,
                speedMps: source?.speedMps,
                trip: trip
            )
            trip.points.append(point)
            context.insert(point)
        }
        trip.invalidatePointCaches()
        TripDetailViewModel.invalidateSpeedSegmentCache(for: trip.id)

        let preservedSpeedCount = trip.sortedPoints.filter { ($0.speedMps ?? 0) > 0 }.count
        DevLog.shared.log(
            .tripDetail,
            "simplify trip=\(trip.id.uuidString.prefix(8)) points \(sorted.count)→\(simplified.count), speedMps on \(preservedSpeedCount)/\(simplified.count) points"
        )
        if preservedSpeedCount == 0, simplified.count >= 2 {
            DevLog.shared.warning(
                .tripDetail,
                "simplify left no speed data — trip detail speed chart will be hidden and map colors may be uniform"
            )
        }
    }

    private static func nearestSourcePoint(
        to coordinate: CLLocationCoordinate2D,
        in source: [TripPoint]
    ) -> TripPoint? {
        guard !source.isEmpty else { return nil }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return source.min { lhs, rhs in
            lhs.location.distance(from: target) < rhs.location.distance(from: target)
        }
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
