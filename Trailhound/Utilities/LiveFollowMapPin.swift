import CoreLocation
import Foundation

/// Session-local map pins for live follow (not a SwiftData schema change).
enum LiveFollowMapPinKind: String, Equatable {
    case start
    case pause
    case tripStop
}

struct LiveFollowMapPin: Identifiable, Equatable {
    let id: String
    let kind: LiveFollowMapPinKind
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(id: String, kind: LiveFollowMapPinKind, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.kind = kind
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    static func == (lhs: LiveFollowMapPin, rhs: LiveFollowMapPin) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.latitude == rhs.latitude
            && lhs.longitude == rhs.longitude
    }
}

/// Builds the pin list shown on the live follow map.
enum LiveFollowMapPinBuilder {
    /// Start pin once from the first breadcrumb / trip start. Pause pins accumulate;
    /// resume must not remove them. Trip stops from automatic dwell detection are included.
    static func pins(
        startCoordinate: CLLocationCoordinate2D?,
        pauseCoordinates: [CLLocationCoordinate2D],
        tripStopCoordinates: [CLLocationCoordinate2D]
    ) -> [LiveFollowMapPin] {
        var result: [LiveFollowMapPin] = []
        if let startCoordinate {
            result.append(
                LiveFollowMapPin(
                    id: "start",
                    kind: .start,
                    coordinate: startCoordinate
                )
            )
        }
        for (index, coordinate) in pauseCoordinates.enumerated() {
            result.append(
                LiveFollowMapPin(
                    id: "pause-\(index)",
                    kind: .pause,
                    coordinate: coordinate
                )
            )
        }
        for (index, coordinate) in tripStopCoordinates.enumerated() {
            result.append(
                LiveFollowMapPin(
                    id: "stop-\(index)",
                    kind: .tripStop,
                    coordinate: coordinate
                )
            )
        }
        return result
    }
}
