import Foundation

/// Parking-stop markers during a trip — not GPS recording quality.
enum RecordingConfiguration {
    /// Below this speed (km/h), the car counts as stopped for parking-stop markers only.
    static let stopDetectionSpeedKmh: Double = 2
    /// How long speed must stay low before a parking stop is stored on the trip.
    static let minimumParkingStopDurationSeconds: TimeInterval = 120
}
