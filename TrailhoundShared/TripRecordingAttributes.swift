import ActivityKit
import Foundation

struct TripRecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var distanceMeters: Double
        var currentSpeedKmh: Int
        var isPaused: Bool
        /// Side-profile SF Symbol for Dynamic Island / lock banner (fallback `car.side.fill`).
        var vehicleSystemImage: String
        /// `scaleEffect(x:)` so the symbol faces right.
        var vehicleSymbolScaleX: Double
        /// Optional tiny JPEG thumb; omit when using the SF Symbol.
        var vehiclePhotoJPEGData: Data?

        init(
            elapsedSeconds: Int,
            distanceMeters: Double,
            currentSpeedKmh: Int,
            isPaused: Bool,
            vehicleSystemImage: String = "car.side.fill",
            vehicleSymbolScaleX: Double = -1,
            vehiclePhotoJPEGData: Data? = nil
        ) {
            self.elapsedSeconds = elapsedSeconds
            self.distanceMeters = distanceMeters
            self.currentSpeedKmh = currentSpeedKmh
            self.isPaused = isPaused
            self.vehicleSystemImage = vehicleSystemImage
            self.vehicleSymbolScaleX = vehicleSymbolScaleX
            self.vehiclePhotoJPEGData = vehiclePhotoJPEGData
        }
    }

    var startedAt: Date
}
