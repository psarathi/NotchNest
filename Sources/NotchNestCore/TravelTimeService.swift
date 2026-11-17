@preconcurrency import CoreLocation
import Foundation
import MapKit

/// Estimates driving travel time via Apple MapKit / CoreLocation for physical calendar event addresses.
@MainActor
public final class TravelTimeService: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var cachedMinutesByLocation: [String: Int] = [:]
    private var pendingLookups: Set<String> = []
    private var currentLocation: CLLocation?

    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    public func cachedTravelMinutes(for location: String?) -> Int? {
        guard let key = normalizedKey(for: location) else { return nil }
        return cachedMinutesByLocation[key]
    }

    public func estimateTravelTimesIfPossible(
        for events: [CalendarEventItem],
        onResolved: @escaping @MainActor (String, Int) -> Void
    ) {
        let physicalEvents = events.filter {
            !$0.isAllDay && $0.meetingURL == nil && normalizedKey(for: $0.location) != nil
        }
        guard !physicalEvents.isEmpty else { return }

        let auth = locationManager.authorizationStatus
        if auth == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            return
        }
        guard auth == .authorized || auth == .authorizedAlways else { return }

        if currentLocation == nil {
            locationManager.requestLocation()
        }

        for event in physicalEvents {
            guard let location = normalizedKey(for: event.location) else { continue }
            if let cached = cachedMinutesByLocation[location] {
                onResolved(location, cached)
                continue
            }
            guard !pendingLookups.contains(location) else { continue }
            pendingLookups.insert(location)

            Task {
                defer { self.pendingLookups.remove(location) }
                guard let minutes = await self.computeDrivingMinutes(to: location) else { return }
                self.cachedMinutesByLocation[location] = minutes
                onResolved(location, minutes)
            }
        }
    }

    private func computeDrivingMinutes(to destinationAddress: String) async -> Int? {
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = destinationAddress
        let search = MKLocalSearch(request: searchRequest)

        guard let response = try? await search.start(),
              let destinationItem = response.mapItems.first
        else {
            return nil
        }

        let sourceItem: MKMapItem
        if let loc = currentLocation ?? locationManager.location {
            sourceItem = MKMapItem(placemark: MKPlacemark(coordinate: loc.coordinate))
        } else {
            sourceItem = MKMapItem.forCurrentLocation()
        }

        let directionsRequest = MKDirections.Request()
        directionsRequest.source = sourceItem
        directionsRequest.destination = destinationItem
        directionsRequest.transportType = .automobile

        let directions = MKDirections(request: directionsRequest)
        guard let eta = try? await directions.calculateETA() else {
            return nil
        }
        return max(1, Int(ceil(eta.expectedTravelTime / 60)))
    }

    private func normalizedKey(for location: String?) -> String? {
        guard let raw = location?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 4,
              !raw.lowercased().contains("http://"),
              !raw.lowercased().contains("https://"),
              !raw.lowercased().contains("zoom"),
              !raw.lowercased().contains("meet.google"),
              !raw.lowercased().contains("teams.microsoft")
        else {
            return nil
        }
        return raw
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.currentLocation = latest
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silently ignore transient CoreLocation lookup failures
    }
}
