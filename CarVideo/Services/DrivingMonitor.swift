import CoreLocation
import Observation

/// Is the car moving? CarPlay doesn't say, so this goes by GPS speed: faster than walking pace for a few
/// readings in a row counts as driving, and the car screen hides video (audio keeps playing) until the car
/// stops. Only runs while CarPlay is connected and the setting is on. Without location access it never
/// reports driving, rather than blocking video it can't judge.
@Observable
@MainActor
final class DrivingMonitor {
    static let shared = DrivingMonitor()

    private(set) var isMoving = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let delegate = LocationDelegate()
    @ObservationIgnored private var running = false
    @ObservationIgnored private var agreeing = 0

    /// About 11 km/h.
    private let movingSpeed: CLLocationSpeed = 3
    /// Consecutive readings needed before switching, so one bad fix at a red light doesn't flip it.
    private let readingsToSwitch = 3

    private init() {
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 5
        manager.activityType = .automotiveNavigation
    }

    /// Whether video is hidden on the car screen right now.
    var hidesVideo: Bool { isMoving && AppSettings.shared.hideVideoWhileDriving }

    func update() {
        let shouldRun = CarConnection.shared.isConnected && AppSettings.shared.hideVideoWhileDriving
        if shouldRun && !running {
            running = true
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            manager.startUpdatingLocation()
            Diagnostics.log("Driving", "Watching speed (location access \(manager.authorizationStatus.rawValue))")
        } else if !shouldRun && running {
            running = false
            manager.stopUpdatingLocation()
            agreeing = 0
            setMoving(false)
        }
    }

    fileprivate func speedReading(_ speed: CLLocationSpeed) {
        guard running, speed >= 0 else { return }
        let moving = speed > movingSpeed
        if moving == isMoving {
            agreeing = 0
            return
        }
        agreeing += 1
        if agreeing >= readingsToSwitch {
            agreeing = 0
            setMoving(moving)
        }
    }

    fileprivate func authorizationChanged(_ status: CLAuthorizationStatus) {
        Diagnostics.log("Driving", "Location access now \(status.rawValue)")
        if status == .denied || status == .restricted {
            setMoving(false)
        }
    }

    private func setMoving(_ moving: Bool) {
        guard moving != isMoving else { return }
        isMoving = moving
        Diagnostics.log("Driving", moving ? "Car is moving: video hidden" : "Car stopped: video shown")
    }
}

/// Location callbacks arrive on the main thread (the manager was created there).
private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let speed = locations.last?.speed else { return }
        MainActor.assumeIsolated { DrivingMonitor.shared.speedReading(speed) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { DrivingMonitor.shared.authorizationChanged(status) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated { Diagnostics.log("Driving", "Location error: \(message)") }
    }
}
