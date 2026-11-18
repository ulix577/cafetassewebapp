#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Platform-neutral restaurant. The iOS app maps its SwiftData `Restaurant` to and from this;
/// the web app stores it directly (IndexedDB).
public struct RestaurantDTO: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var typ: String
    public var name: String
    public var adress: String
    public var rating: Double
    public var comment: String
    public var timestamp: Date
    public var isFavorite: Bool
    public var latitude: Double?
    public var longitude: Double?
    /// Position in the user's café list. Optional so data saved before ordering existed still decodes.
    public var sortOrder: Int?

    public init(
        id: UUID = UUID(),
        typ: String = "",
        name: String = "",
        adress: String = "",
        rating: Double = 0,
        comment: String = "",
        timestamp: Date = Date(),
        isFavorite: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil,
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.typ = typ
        self.name = name
        self.adress = adress
        self.rating = rating
        self.comment = comment
        self.timestamp = timestamp
        self.isFavorite = isFavorite
        self.latitude = latitude
        self.longitude = longitude
        self.sortOrder = sortOrder
    }

    public var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    public static let restaurantTypes = [
        "Café", "Restaurant", "Bistro", "Bäckerei", "Coffee Shop", "Bar", "Konditorei", "Eisdiele"
    ]
}

/// Platform-neutral visit (check-in).
public struct VisitDTO: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var restaurantID: UUID
    public var date: Date
    public var notes: String
    public var rating: Double
    public var photosTaken: Int
    public var spentAmount: Double?
    public var orderNotes: String
    /// Base64-encoded JPEG, same representation as `Visit.photoDataBase64` in the iOS app.
    public var photoDataBase64: String?

    public init(
        id: UUID = UUID(),
        restaurantID: UUID,
        date: Date = Date(),
        notes: String = "",
        rating: Double = 0,
        photosTaken: Int = 0,
        spentAmount: Double? = nil,
        orderNotes: String = "",
        photoDataBase64: String? = nil
    ) {
        self.id = id
        self.restaurantID = restaurantID
        self.date = date
        self.notes = notes
        self.rating = rating
        self.photosTaken = photosTaken
        self.spentAmount = spentAmount
        self.orderNotes = orderNotes
        self.photoDataBase64 = photoDataBase64
    }
}

extension Sequence where Element == VisitDTO {
    /// Mean of the visit ratings that are above zero; 0 if none are rated.
    public var averageRating: Double {
        let rated = filter { $0.rating > 0 }
        guard !rated.isEmpty else { return 0 }
        return rated.reduce(0) { $0 + $1.rating } / Double(rated.count)
    }
}
