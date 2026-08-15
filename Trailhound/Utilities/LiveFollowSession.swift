import CoreLocation
import Foundation

/// Mutable follow session shared by the display-link loop and the MapKit host.
/// Keeps 60 fps camera writes off the SwiftUI dependency graph; only quality badge
/// publishes observation changes (and only when the value actually flips).
@Observable
@MainActor
final class LiveFollowSession {
    /// Pose ticks at display rate — must not invalidate SwiftUI.
    @ObservationIgnored
    var camera = LiveFollowCamera()
    /// MapKit coordinator installs this to receive pose writes without SwiftUI rebuilds.
    @ObservationIgnored
    var onPoseWrite: ((LiveFollowCamera.Pose, CLLocationCoordinate2D?) -> Void)?

    @ObservationIgnored
    weak var locationService: LocationService?

    @ObservationIgnored var isPaused = false
    @ObservationIgnored var isFollowing = true
    @ObservationIgnored var openSettled = false
    @ObservationIgnored var isClosing = false
    @ObservationIgnored var uses3D = true
    @ObservationIgnored var reduceMotion = false

    /// Observed by the HUD badge only when the value changes.
    private(set) var displayedGPSQuality: LocationService.GPSQuality = .lost

    func setDisplayedGPSQuality(_ quality: LocationService.GPSQuality) {
        if displayedGPSQuality != quality {
            displayedGPSQuality = quality
        }
    }

    var vehicleCoordinate: CLLocationCoordinate2D? { camera.center }
    var pose: LiveFollowCamera.Pose? { camera.pose }

    func ingest(location: CLLocation, isPaused: Bool, now: Date = Date()) {
        camera.ingest(location: location, isPaused: isPaused, now: now)
    }

    @discardableResult
    func tick(dt: TimeInterval, now: Date = Date()) -> Bool {
        guard camera.tick(dt: dt, now: now) else { return false }
        if let pose = camera.pose {
            onPoseWrite?(pose, camera.center)
        }
        return true
    }

    /// Display-link entry: ingest latest GPS, advance pose when following.
    func handleDisplayTick(dt: TimeInterval, now: Date = Date()) {
        guard !isClosing else { return }

        if let locationService {
            let quality = locationService.gpsQuality
            if displayedGPSQuality != quality {
                displayedGPSQuality = quality
            }
        }

        camera.uses3D = uses3D
        camera.reduceMotion = reduceMotion

        if let location = locationService?.lastLocation {
            camera.ingest(location: location, isPaused: isPaused, now: now)
        }

        guard openSettled, isFollowing else { return }
        _ = tick(dt: dt, now: now)
    }

    func forceRecenter(location: CLLocation, now: Date = Date()) {
        camera.forceRecenter(location: location, now: now)
        if let pose = camera.pose {
            onPoseWrite?(pose, camera.center)
        }
    }

    func bootstrap(uses3D: Bool, reduceMotion: Bool, location: CLLocation?, tip: CLLocationCoordinate2D?) {
        self.uses3D = uses3D
        self.reduceMotion = reduceMotion
        camera.uses3D = uses3D
        camera.reduceMotion = reduceMotion
        if let location {
            camera.ingest(location: location, isPaused: false)
            camera.forceRecenter(location: location)
            if let pose = camera.pose {
                onPoseWrite?(pose, camera.center)
            }
        } else if let tip {
            let synthetic = CLLocation(
                coordinate: tip,
                altitude: 0,
                horizontalAccuracy: 10,
                verticalAccuracy: 10,
                course: -1,
                courseAccuracy: -1,
                speed: 0,
                speedAccuracy: -1,
                timestamp: Date()
            )
            camera.ingest(location: synthetic, isPaused: false)
            camera.forceRecenter(location: synthetic)
            if let pose = camera.pose {
                onPoseWrite?(pose, camera.center)
            }
        }
    }
}
