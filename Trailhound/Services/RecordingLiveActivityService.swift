import ActivityKit
import Foundation

// Vehicle mark is passed as systemImage / scaleX / photoJPEG primitives only.
@MainActor
enum RecordingLiveActivityService {
    private static let logCategory: DevLogCategory = .widget
    private static var lastUpdateAt: Date?
    private static var lastPublishedIsPaused: Bool?
    private static let minimumUpdateInterval: TimeInterval = 3
    private static var operationChain: Task<Void, Never>?

    /// Ends orphan Live Activities left over from a prior process (e.g. Xcode debug restart).
    static func reconcileAfterLaunch(hasActiveSession: Bool) async {
        await runSerially {
            guard !hasActiveSession else { return }
            guard !Activity<TripRecordingAttributes>.activities.isEmpty else { return }
            await endAllImmediately()
        }
    }

    static func start(
        startedAt: Date,
        elapsed: TimeInterval = 0,
        distanceMeters: Double = 0,
        currentSpeedKmh: Int = 0,
        isPaused: Bool = false,
        vehicleSystemImage: String = "car.side.fill",
        vehicleSymbolScaleX: Double = -1,
        vehiclePhotoJPEGData: Data? = nil
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        enqueue {
            await endAllImmediately()
            await requestActivity(
                startedAt: startedAt,
                elapsed: elapsed,
                distanceMeters: distanceMeters,
                currentSpeedKmh: currentSpeedKmh,
                isPaused: isPaused,
                vehicleSystemImage: vehicleSystemImage,
                vehicleSymbolScaleX: vehicleSymbolScaleX,
                vehiclePhotoJPEGData: vehiclePhotoJPEGData,
                logMessage: "Live Activity started"
            )
            lastUpdateAt = nil
            lastPublishedIsPaused = isPaused
        }
    }

    /// Starts (or confirms) a Live Activity on the *current* task.
    /// Required when invoking from a `LiveActivityIntent`: background
    /// `Activity.request` is only authorized on that intent's `perform()` task,
    /// not on a detached/enqueued Task (which hits `visibility` and fails until
    /// the app is later opened).
    static func startOnCurrentTask(
        startedAt: Date,
        elapsed: TimeInterval = 0,
        distanceMeters: Double = 0,
        currentSpeedKmh: Int = 0,
        isPaused: Bool = false,
        vehicleSystemImage: String = "car.side.fill",
        vehicleSymbolScaleX: Double = -1,
        vehiclePhotoJPEGData: Data? = nil
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        await operationChain?.value
        if !Activity<TripRecordingAttributes>.activities.isEmpty { return }
        await endAllImmediately()
        await requestActivity(
            startedAt: startedAt,
            elapsed: elapsed,
            distanceMeters: distanceMeters,
            currentSpeedKmh: currentSpeedKmh,
            isPaused: isPaused,
            vehicleSystemImage: vehicleSystemImage,
            vehicleSymbolScaleX: vehicleSymbolScaleX,
            vehiclePhotoJPEGData: vehiclePhotoJPEGData,
            logMessage: "Live Activity started (intent)"
        )
        lastUpdateAt = nil
        lastPublishedIsPaused = isPaused
    }

    /// Re-creates the Live Activity if recording is active but the system dismissed it.
    static func ensureActiveIfNeeded(
        startedAt: Date,
        elapsed: TimeInterval,
        distanceMeters: Double,
        currentSpeedKmh: Int,
        isPaused: Bool,
        vehicleSystemImage: String = "car.side.fill",
        vehicleSymbolScaleX: Double = -1,
        vehiclePhotoJPEGData: Data? = nil
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        enqueue {
            await dedupeActivitiesIfNeeded()
            guard Activity<TripRecordingAttributes>.activities.isEmpty else { return }
            DevLog.shared.log(logCategory, "Live Activity missing during recording; restarting", level: .warning)
            await requestActivity(
                startedAt: startedAt,
                elapsed: elapsed,
                distanceMeters: distanceMeters,
                currentSpeedKmh: currentSpeedKmh,
                isPaused: isPaused,
                vehicleSystemImage: vehicleSystemImage,
                vehicleSymbolScaleX: vehicleSymbolScaleX,
                vehiclePhotoJPEGData: vehiclePhotoJPEGData,
                logMessage: "Live Activity restarted"
            )
            lastUpdateAt = nil
            lastPublishedIsPaused = isPaused
        }
    }

    static func update(
        elapsed: TimeInterval,
        distanceMeters: Double,
        currentSpeedKmh: Int,
        isPaused: Bool,
        force: Bool = false,
        vehicleSystemImage: String = "car.side.fill",
        vehicleSymbolScaleX: Double = -1,
        vehiclePhotoJPEGData: Data? = nil
    ) {
        let pauseStateChanged = lastPublishedIsPaused != isPaused
        let now = Date()
        if !force,
           !pauseStateChanged,
           let lastUpdateAt,
           now.timeIntervalSince(lastUpdateAt) < minimumUpdateInterval {
            return
        }
        lastUpdateAt = now
        lastPublishedIsPaused = isPaused

        let state = TripRecordingAttributes.ContentState(
            elapsedSeconds: Int(elapsed.rounded()),
            distanceMeters: distanceMeters,
            currentSpeedKmh: currentSpeedKmh,
            isPaused: isPaused,
            vehicleSystemImage: vehicleSystemImage,
            vehicleSymbolScaleX: vehicleSymbolScaleX,
            vehiclePhotoJPEGData: vehiclePhotoJPEGData
        )
        let safeState = payloadSafe(state)
        let content = ActivityContent(state: safeState, staleDate: nil)

        enqueue {
            await dedupeActivitiesIfNeeded()
            guard !Activity<TripRecordingAttributes>.activities.isEmpty else { return }
            for activity in Activity<TripRecordingAttributes>.activities {
                // Live Activity intent already painted pause/resume; a second near-identical
                // update restarts the control morph and reads as stutter.
                if Self.isRedundantPublish(current: activity.content.state, next: safeState) {
                    continue
                }
                await activity.update(content)
            }
        }
    }

    /// True when a publish would not change what the banner shows in a meaningful way.
    private static func isRedundantPublish(
        current: TripRecordingAttributes.ContentState,
        next: TripRecordingAttributes.ContentState
    ) -> Bool {
        guard current.isPaused == next.isPaused,
              current.elapsedSeconds == next.elapsedSeconds,
              current.currentSpeedKmh == next.currentSpeedKmh,
              current.vehicleSystemImage == next.vehicleSystemImage,
              current.vehicleSymbolScaleX == next.vehicleSymbolScaleX,
              current.vehiclePhotoJPEGData == next.vehiclePhotoJPEGData,
              abs(current.distanceMeters - next.distanceMeters) < 0.5 else {
            return false
        }
        return true
    }

    static func stop() {
        lastUpdateAt = nil
        lastPublishedIsPaused = nil
        enqueue {
            await endAllImmediately()
        }
    }

    private static func enqueue(_ operation: @MainActor @escaping () async -> Void) {
        let waitFor = operationChain
        operationChain = Task { @MainActor in
            await waitFor?.value
            await operation()
        }
    }

    private static func runSerially(_ operation: @MainActor @escaping () async -> Void) async {
        let waitFor = operationChain
        let task = Task { @MainActor in
            await waitFor?.value
            await operation()
        }
        operationChain = task
        await task.value
    }

    private static func requestActivity(
        startedAt: Date,
        elapsed: TimeInterval,
        distanceMeters: Double,
        currentSpeedKmh: Int,
        isPaused: Bool,
        vehicleSystemImage: String,
        vehicleSymbolScaleX: Double,
        vehiclePhotoJPEGData: Data?,
        logMessage: String
    ) async {
        let attributes = TripRecordingAttributes(startedAt: startedAt)
        let state = TripRecordingAttributes.ContentState(
            elapsedSeconds: Int(elapsed.rounded()),
            distanceMeters: distanceMeters,
            currentSpeedKmh: currentSpeedKmh,
            isPaused: isPaused,
            vehicleSystemImage: vehicleSystemImage,
            vehicleSymbolScaleX: vehicleSymbolScaleX,
            vehiclePhotoJPEGData: vehiclePhotoJPEGData
        )
        do {
            _ = try Activity.request(attributes: attributes, content: .init(state: payloadSafe(state), staleDate: nil))
            DevLog.shared.log(logCategory, logMessage)
            await dedupeActivitiesIfNeeded()
        } catch {
            // Background `AppIntent` (non-LiveActivityIntent) hits `.visibility`; the
            // Shortcuts path retries via `startOnCurrentTask` on the intent task.
            let level: DevLogLevel = (error as? ActivityAuthorizationError) == .visibility
                ? .warning
                : .error
            DevLog.shared.log(
                logCategory,
                "Live Activity start failed: \(error.localizedDescription)",
                level: level
            )
        }
    }

    private static func payloadSafe(
        _ state: TripRecordingAttributes.ContentState
    ) -> TripRecordingAttributes.ContentState {
        guard let photoData = state.vehiclePhotoJPEGData,
              !RecordingVehicleMarkSnapshot.fitsLiveActivityPayload(photoData),
              let encoded = try? JSONEncoder().encode(state) else {
            return state
        }
        var trimmed = state
        trimmed.vehiclePhotoJPEGData = nil
        DevLog.shared.log(
            logCategory,
            "Live Activity payload \(encoded.count) B over budget; vehicle photo dropped",
            level: .warning
        )
        return trimmed
    }

    private static func dedupeActivitiesIfNeeded() async {
        let activities = Activity<TripRecordingAttributes>.activities
        guard activities.count > 1 else { return }
        DevLog.shared.log(
            logCategory,
            "Live Activity duplicate count=\(activities.count); ending extras",
            level: .warning
        )
        for activity in activities.dropLast() {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private static func endAllImmediately() async {
        for activity in Activity<TripRecordingAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
