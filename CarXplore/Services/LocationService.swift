import CoreLocation
import Foundation

/// Wrapper om CLLocationManager, sat op til bilkørsel og til at køre i baggrunden.
@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isTracking = false
    @Published private(set) var lastLocation: CLLocation?

    /// Kaldes med nye positioner, mens en tur er i gang.
    var onLocations: (([CLLocation]) -> Void)?

    private let manager = CLLocationManager()
    private var startWhenAuthorized = false

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 20
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    func startTrip() {
        switch authorization {
        case .notDetermined:
            startWhenAuthorized = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            // Med UIBackgroundModes=location fortsætter en tur, der er startet
            // i forgrunden, også når appen går i baggrunden (blå indikator).
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.startUpdatingLocation()
            isTracking = true
        default:
            break
        }
    }

    func stopTrip() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isTracking = false
    }

    /// Viser kun brugerens position på kortet uden at registrere en tur.
    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        authorization = status
        if startWhenAuthorized, isAuthorized {
            startWhenAuthorized = false
            startTrip()
        } else if !isAuthorized, isTracking {
            stopTrip()
        }
    }

    private func received(_ locations: [CLLocation]) {
        lastLocation = locations.last
        if isTracking {
            onLocations?(locations)
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationChanged(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.received(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("CarXplore: lokationsfejl: \(error.localizedDescription)")
    }
}
