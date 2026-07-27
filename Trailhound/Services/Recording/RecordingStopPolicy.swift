import Foundation

enum RecordingStopPolicy {
    enum StopReason {
        case manual
    }

    static func shouldSaveTrip(
        saveTrip: Bool,
        reason: StopReason,
        duration: TimeInterval,
        distanceMeters: Double,
        minimumDurationSeconds: TimeInterval,
        minimumDistanceMeters: Double
    ) -> Bool {
        guard saveTrip else { return false }
        if reason == .manual { return true }
        return duration >= minimumDurationSeconds && distanceMeters >= minimumDistanceMeters
    }
}
