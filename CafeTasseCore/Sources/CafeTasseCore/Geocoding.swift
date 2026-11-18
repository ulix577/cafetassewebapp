#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A place found by an address lookup.
public struct GeocodedPlace: Equatable, Sendable {
    public var coordinate: Coordinate
    /// Human-readable match from the geocoder, shown so the user can confirm it is the right place.
    public var displayName: String

    public init(coordinate: Coordinate, displayName: String) {
        self.coordinate = coordinate
        self.displayName = displayName
    }
}

/// Parses responses of the Nominatim `/search?format=json` (or `jsonv2`) endpoint.
/// The network call itself lives in the web target; this part is platform independent and tested.
public enum GeocodingResponse {
    private struct Item: Decodable {
        // Nominatim sends coordinates as strings, e.g. "lat": "52.5170365".
        let lat: String
        let lon: String
        let display_name: String?
    }

    /// The first usable match, or nil for an empty result, malformed JSON or out-of-range coordinates.
    public static func firstPlace(in data: Data) -> GeocodedPlace? {
        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { return nil }
        for item in items {
            guard let latitude = Double(item.lat), let longitude = Double(item.lon),
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else { continue }
            return GeocodedPlace(
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                displayName: item.display_name ?? ""
            )
        }
        return nil
    }
}
