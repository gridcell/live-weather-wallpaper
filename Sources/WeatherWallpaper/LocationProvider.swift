import CoreLocation
import Foundation

struct Coordinate: Codable {
    var latitude: Double
    var longitude: Double
}

/// Resolves the user's location: Location Services first, then IP geolocation,
/// then whatever was last known.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: ((Coordinate?) -> Void)?
    private let cacheKey = "lastCoordinate"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentCoordinate() async -> Coordinate? {
        var resolved = await systemCoordinate()
        if resolved == nil { resolved = await ipCoordinate() }
        if let coordinate = resolved {
            if let data = try? JSONEncoder().encode(coordinate) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
            return coordinate
        }
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Coordinate.self, from: data)
    }

    private func systemCoordinate() async -> Coordinate? {
        let status = manager.authorizationStatus
        guard status != .denied, status != .restricted, pending == nil else { return nil }
        return await withCheckedContinuation { continuation in
            pending = { continuation.resume(returning: $0) }
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
            // Don't wait forever on an unanswered permission prompt or a slow fix.
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.finish(nil)
            }
        }
    }

    private func finish(_ coordinate: Coordinate?) {
        pending?(coordinate)
        pending = nil
    }

    private func ipCoordinate() async -> Coordinate? {
        guard let url = URL(string: "https://ipapi.co/json/"),
              let (data, _) = try? await URLSession.shared.data(from: url)
        else { return nil }
        return try? JSONDecoder().decode(Coordinate.self, from: data)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.pending != nil else { return }
            switch manager.authorizationStatus {
            case .notDetermined: break
            case .denied, .restricted: self.finish(nil)
            default: manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        Task { @MainActor in self.finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
