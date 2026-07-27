import CoreLocation
import Foundation

@Observable
final class LocationService: NSObject {
    enum AuthorizationState: Equatable {
        case notDetermined
        case authorizedWhenInUse
        case authorizedAlways
        case denied
        case restricted
    }

    enum TrackingMode {
        case off
        case full
    }

    enum GPSQuality: Equatable {
        case good
        case weak
        case lost
    }

    private(set) var authorizationState: AuthorizationState = .notDetermined
    private(set) var lastLocation: CLLocation?
    private(set) var trackingMode: TrackingMode = .off

    var gpsQuality: GPSQuality {
        guard let lastLocation else { return .lost }
        let age = Date().timeIntervalSince(lastLocation.timestamp)
        if age > 30 { return .lost }
        if lastLocation.horizontalAccuracy < 0 || lastLocation.horizontalAccuracy > 80 { return .weak }
        return .good
    }

    var onLocationUpdate: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()
    private var isUpdating = false

    var canRecordInBackground: Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        updateAuthorizationState(from: manager.authorizationStatus)
    }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func startTracking() {
        trackingMode = .full
        manager.pausesLocationUpdatesAutomatically = false
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        startIfNeeded()
    }

    func stopTracking() {
        trackingMode = .off
        manager.pausesLocationUpdatesAutomatically = true
        applyBackgroundConfiguration()
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
    }

    private func startIfNeeded() {
        guard !isUpdating else {
            applyBackgroundConfiguration()
            return
        }
        applyBackgroundConfiguration()
        isUpdating = true
        manager.startUpdatingLocation()
    }

    private func applyBackgroundConfiguration() {
        let canUseBackground = manager.authorizationStatus == .authorizedAlways
        let needsBackground = canUseBackground && trackingMode != .off

        manager.allowsBackgroundLocationUpdates = needsBackground
        manager.showsBackgroundLocationIndicator = trackingMode == .full && needsBackground
    }

    private func updateAuthorizationState(from status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways:
            authorizationState = .authorizedAlways
        case .authorizedWhenInUse:
            authorizationState = .authorizedWhenInUse
        case .denied:
            authorizationState = .denied
        case .restricted:
            authorizationState = .restricted
        case .notDetermined:
            authorizationState = .notDetermined
        @unknown default:
            authorizationState = .notDetermined
        }
    }

    private func isLocationUsable(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0 else { return false }
        if trackingMode == .full, location.horizontalAccuracy > 250 { return false }
        if Date().timeIntervalSince(location.timestamp) > 60 { return false }
        return true
    }
}

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationState(from: manager.authorizationStatus)
        applyBackgroundConfiguration()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        guard isLocationUsable(location) else { return }
        lastLocation = location
        onLocationUpdate?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("Location error: \(error.localizedDescription)")
        #endif
    }
}
