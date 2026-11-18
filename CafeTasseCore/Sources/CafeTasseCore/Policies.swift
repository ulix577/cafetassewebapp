#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Why a check-in is or isn't allowed. Mirrors the iOS `CheckInValidationResult`
/// without the UI parts (SwiftUI `Color`, SF Symbol names, localized strings).
public enum CheckInValidation: Equatable, Sendable {
    case allowed
    case alreadyCheckedInToday(visitDate: Date)
    case tooFarAway(distance: Double)
    case noLocation
    case noRestaurantCoordinates

    public var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }
}

/// Check-in rules. Same precedence as `RestaurantDetailView.validateCheckIn()` in the iOS app:
/// already checked in today, then missing user location, then missing restaurant coordinates, then distance.
public struct CheckInPolicy: Equatable, Sendable {
    public static let defaultRadius: Double = 10

    /// Maximum distance in meters between guest and restaurant.
    public var radius: Double
    /// When false the location checks are skipped (the "requireLocationForCheckIn" setting).
    public var requiresLocation: Bool

    public init(radius: Double = CheckInPolicy.defaultRadius, requiresLocation: Bool = true) {
        self.radius = radius > 0 ? radius : Self.defaultRadius
        self.requiresLocation = requiresLocation
    }

    /// True when the device reports a position error larger than the check-in radius. Then a
    /// "too far away" result may just mean a weak GPS signal, and the guest should be told so.
    public func isAccuracyTooLow(_ accuracy: Double?) -> Bool {
        guard let accuracy, accuracy.isFinite, accuracy > 0 else { return false }
        return accuracy > radius
    }

    public func validate(
        restaurantCoordinate: Coordinate?,
        userCoordinate: Coordinate?,
        existingVisitDates: [Date],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CheckInValidation {
        if let today = existingVisitDates.first(where: { calendar.isDate($0, inSameDayAs: now) }) {
            return .alreadyCheckedInToday(visitDate: today)
        }
        guard requiresLocation else { return .allowed }

        guard let userCoordinate else { return .noLocation }
        guard let restaurantCoordinate else { return .noRestaurantCoordinates }

        let distance = userCoordinate.distance(to: restaurantCoordinate)
        return distance <= radius ? .allowed : .tooFarAway(distance: distance)
    }
}

/// Web app rule: visits can only be swiped away once a restaurant has at least 10 of them.
public enum VisitDeletionPolicy {
    public static let minimumVisitsForDeletion = 10

    public static func canDeleteVisits(visitCount: Int) -> Bool {
        visitCount >= minimumVisitsForDeletion
    }
}
