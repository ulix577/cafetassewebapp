#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#elseif canImport(Glibc)
import Glibc
#endif

/// A WGS84 coordinate. Replaces `CLLocation` so the logic also builds for WebAssembly.
public struct Coordinate: Codable, Equatable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Mean Earth radius in meters.
    private static let earthRadius = 6_371_008.8

    /// Great-circle distance in meters (haversine formula).
    public func distance(to other: Coordinate) -> Double {
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = lat2 - lat1
        let deltaLon = (other.longitude - longitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * Self.earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// Formats a distance in meters for display ("42 m", "1.3 km").
/// Avoids `String(format:)` so it behaves the same on every platform.
public func formatDistance(_ meters: Double) -> String {
    if meters < 1000 {
        return "\(Int(meters.rounded())) m"
    }
    let tenthsOfKm = Int((meters / 100).rounded())
    return "\(tenthsOfKm / 10).\(tenthsOfKm % 10) km"
}
