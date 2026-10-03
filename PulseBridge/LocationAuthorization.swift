@preconcurrency import CoreLocation
import Observation

/// Location permission as the UI shows it; follows changes made in Settings while the app runs.
@MainActor
@Observable
final class LocationAuthorization: NSObject {
    private(set) var status: CLAuthorizationStatus
    private(set) var accuracy: CLAccuracyAuthorization
    @ObservationIgnored private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        status = manager.authorizationStatus
        accuracy = manager.accuracyAuthorization
        super.init()
        manager.delegate = self
    }
}

extension LocationAuthorization: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus, accuracy = manager.accuracyAuthorization
        MainActor.assumeIsolated {
            self.status = status
            self.accuracy = accuracy
        }
    }
}
