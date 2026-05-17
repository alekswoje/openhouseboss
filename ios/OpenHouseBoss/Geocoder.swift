import CoreLocation
import Foundation

// Apple CLGeocoder wrapper. Used at session-create time to resolve the
// property address to (lat, lon) so the backend can fetch point-resolution
// weather from Open-Meteo. We deliberately use Apple's geocoder (free,
// no key, no network round-trip to our backend) rather than running our
// own server-side geocoder — keeps the dependency surface zero and the
// agent's address never leaves their device for this purpose.
//
// Failure-tolerant by design: geocoding can fail for new construction,
// rural addresses, typos, no connectivity, or Apple's quota limits.
// All of those return nil; the caller must NOT block the recording
// upload on a successful geocode. The backend silently skips weather
// enrichment when lat/lon are missing.
enum Geocoder {
    // Apple recommends reusing a single CLGeocoder instance per app for
    // its rate limiting. We're not making many requests so a fresh
    // instance per call is fine, but stashing one keeps allocations down.
    private static let geocoder = CLGeocoder()

    // Returns the most-likely (lat, lon) for the given postal address,
    // or nil on any failure. Times out after ~6 seconds so a slow
    // Apple Maps lookup can't delay the session-upload flow.
    static func coordinate(forAddress address: String) async -> (latitude: Double, longitude: Double)? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Race the geocode against a hard timeout. Apple's API has no
        // built-in timeout knob — without this a flaky-network geocode
        // could hang the recording upload for a minute+.
        return await withTaskGroup(of: (latitude: Double, longitude: Double)?.self) { group in
            group.addTask {
                do {
                    let placemarks = try await geocoder.geocodeAddressString(trimmed)
                    guard let loc = placemarks.first?.location else { return nil }
                    return (loc.coordinate.latitude, loc.coordinate.longitude)
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(6))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
