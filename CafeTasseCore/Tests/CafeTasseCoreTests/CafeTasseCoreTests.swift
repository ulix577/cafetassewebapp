import Foundation
import Testing
@testable import CafeTasseCore

@Suite("Coordinate")
struct CoordinateTests {
    @Test func distanceToSelfIsZero() {
        let c = Coordinate(latitude: 52.52, longitude: 13.405)
        #expect(c.distance(to: c) == 0)
    }

    @Test func berlinToHamburgIsAbout255km() {
        let berlin = Coordinate(latitude: 52.5200, longitude: 13.4050)
        let hamburg = Coordinate(latitude: 53.5511, longitude: 9.9937)
        let km = berlin.distance(to: hamburg) / 1000
        #expect(abs(km - 255) < 3)
    }

    @Test func oneThousandthDegreeLatitudeIsAbout111m() {
        let a = Coordinate(latitude: 50.000, longitude: 8)
        let b = Coordinate(latitude: 50.001, longitude: 8)
        #expect(abs(a.distance(to: b) - 111.2) < 0.5)
    }

    @Test func formatsDistances() {
        #expect(formatDistance(0) == "0 m")
        #expect(formatDistance(42.4) == "42 m")
        #expect(formatDistance(999.4) == "999 m")
        #expect(formatDistance(1000) == "1.0 km")
        #expect(formatDistance(1349) == "1.3 km")
        #expect(formatDistance(12_500) == "12.5 km")
    }
}

@Suite("CheckInPolicy")
struct CheckInPolicyTests {
    private let cafe = Coordinate(latitude: 50.0, longitude: 8.0)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func allowedWhenWithinRadius() {
        let near = Coordinate(latitude: 50.00003, longitude: 8.0) // about 3 m
        let result = CheckInPolicy().validate(
            restaurantCoordinate: cafe, userCoordinate: near,
            existingVisitDates: [], now: now, calendar: calendar)
        #expect(result == .allowed)
    }

    @Test func tooFarReportsDistance() {
        let far = Coordinate(latitude: 50.001, longitude: 8.0) // about 111 m
        let result = CheckInPolicy().validate(
            restaurantCoordinate: cafe, userCoordinate: far,
            existingVisitDates: [], now: now, calendar: calendar)
        guard case .tooFarAway(let distance) = result else {
            Issue.record("expected tooFarAway, got \(result)")
            return
        }
        #expect(abs(distance - 111.2) < 0.5)
    }

    @Test func alreadyCheckedInTodayWinsOverLocation() {
        let result = CheckInPolicy().validate(
            restaurantCoordinate: cafe, userCoordinate: nil,
            existingVisitDates: [now.addingTimeInterval(-60)], now: now, calendar: calendar)
        #expect(result == .alreadyCheckedInToday(visitDate: now.addingTimeInterval(-60)))
    }

    @Test func visitFromYesterdayDoesNotBlock() {
        let result = CheckInPolicy().validate(
            restaurantCoordinate: cafe, userCoordinate: cafe,
            existingVisitDates: [now.addingTimeInterval(-86_400)], now: now, calendar: calendar)
        #expect(result == .allowed)
    }

    @Test func missingUserLocation() {
        let result = CheckInPolicy().validate(
            restaurantCoordinate: cafe, userCoordinate: nil,
            existingVisitDates: [], now: now, calendar: calendar)
        #expect(result == .noLocation)
    }

    @Test func missingRestaurantCoordinates() {
        let result = CheckInPolicy().validate(
            restaurantCoordinate: nil, userCoordinate: cafe,
            existingVisitDates: [], now: now, calendar: calendar)
        #expect(result == .noRestaurantCoordinates)
    }

    @Test func locationNotRequiredSkipsLocationChecks() {
        let policy = CheckInPolicy(requiresLocation: false)
        let result = policy.validate(
            restaurantCoordinate: nil, userCoordinate: nil,
            existingVisitDates: [], now: now, calendar: calendar)
        #expect(result == .allowed)
    }

    @Test func accuracyIsTooLowOnlyWhenWorseThanRadius() {
        let policy = CheckInPolicy(radius: 10)
        #expect(policy.isAccuracyTooLow(35))
        #expect(policy.isAccuracyTooLow(10.5))
        #expect(!policy.isAccuracyTooLow(10))
        #expect(!policy.isAccuracyTooLow(4))
        #expect(!policy.isAccuracyTooLow(nil))
        #expect(!policy.isAccuracyTooLow(0))
        #expect(!policy.isAccuracyTooLow(.infinity))
        #expect(!policy.isAccuracyTooLow(.nan))
    }

    @Test func nonPositiveRadiusFallsBackToDefault() {
        #expect(CheckInPolicy(radius: 0).radius == CheckInPolicy.defaultRadius)
        #expect(CheckInPolicy(radius: -5).radius == CheckInPolicy.defaultRadius)
    }
}

@Suite("VisitDeletionPolicy")
struct VisitDeletionPolicyTests {
    @Test(arguments: [(0, false), (1, false), (9, false), (10, true), (11, true), (250, true)])
    func deletionEnabledFromTenVisits(count: Int, expected: Bool) {
        #expect(VisitDeletionPolicy.canDeleteVisits(visitCount: count) == expected)
    }
}

@Suite("Models")
struct ModelTests {
    @Test func codableRoundTrip() throws {
        let restaurant = RestaurantDTO(name: "Café Tasse", latitude: 50, longitude: 8)
        let visit = VisitDTO(restaurantID: restaurant.id, rating: 4, photoDataBase64: "AAAA")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let r2 = try decoder.decode(RestaurantDTO.self, from: encoder.encode(restaurant))
        let v2 = try decoder.decode(VisitDTO.self, from: encoder.encode(visit))
        #expect(r2.id == restaurant.id)
        #expect(r2.coordinate == Coordinate(latitude: 50, longitude: 8))
        #expect(v2.restaurantID == restaurant.id)
        #expect(v2.photoDataBase64 == "AAAA")
    }

    @Test func averageRatingIgnoresUnrated() {
        let id = UUID()
        let visits = [
            VisitDTO(restaurantID: id, rating: 4),
            VisitDTO(restaurantID: id, rating: 0),
            VisitDTO(restaurantID: id, rating: 2)
        ]
        #expect(visits.averageRating == 3)
        #expect([VisitDTO]().averageRating == 0)
    }
}

@Suite("GeocodingResponse")
struct GeocodingResponseTests {
    private func parse(_ json: String) -> GeocodedPlace? {
        GeocodingResponse.firstPlace(in: Data(json.utf8))
    }

    @Test func parsesNominatimResult() {
        let place = parse("""
        [{"place_id":1,"lat":"52.5170365","lon":"13.3888599","display_name":"Brandenburger Tor, Berlin, Deutschland"}]
        """)
        #expect(place?.coordinate == Coordinate(latitude: 52.5170365, longitude: 13.3888599))
        #expect(place?.displayName == "Brandenburger Tor, Berlin, Deutschland")
    }

    @Test func emptyResultIsNil() {
        #expect(parse("[]") == nil)
    }

    @Test func malformedJSONIsNil() {
        #expect(parse("not json") == nil)
        #expect(parse("{\"error\":\"rate limited\"}") == nil)
        #expect(parse("") == nil)
    }

    @Test func skipsUnusableEntriesAndTakesNextValidOne() {
        let place = parse("""
        [{"lat":"abc","lon":"1","display_name":"bad"},
         {"lat":"91","lon":"0","display_name":"out of range"},
         {"lat":"48.1","lon":"11.5","display_name":"München"}]
        """)
        #expect(place?.displayName == "München")
    }

    @Test func missingDisplayNameBecomesEmpty() {
        let place = parse("[{\"lat\":\"1.5\",\"lon\":\"-2.5\"}]")
        #expect(place?.coordinate == Coordinate(latitude: 1.5, longitude: -2.5))
        #expect(place?.displayName == "")
    }
}
