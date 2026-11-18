import CafeTasseCore
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import JavaScriptKit

/// IndexedDB persistence. Records are stored as JSON strings keyed by UUID, in two object stores.
/// Everything stays in the guest's browser; there is no server.
final class Store {
    private enum Name {
        static let database = "cafetasse"
        static let restaurants = "restaurants"
        static let visits = "visits"
    }

    private let database: JSObject

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private init(database: JSObject) {
        self.database = database
    }

    static func open() async throws -> Store {
        let request = JSObject.global.indexedDB.object!.open!(Name.database, 1).object!
        request.onupgradeneeded = .object(JSClosure { _ in
            let database = request.result.object!
            _ = database.createObjectStore!(Name.restaurants)
            _ = database.createObjectStore!(Name.visits)
            return .undefined
        })
        let result = try await result(of: request)
        return Store(database: result.object!)
    }

    // MARK: - Reads

    func loadRestaurants() async throws -> [RestaurantDTO] {
        try await loadAll(from: Name.restaurants)
    }

    func loadVisits() async throws -> [VisitDTO] {
        try await loadAll(from: Name.visits)
    }

    // MARK: - Writes

    func save(_ restaurant: RestaurantDTO) async throws {
        try await put(restaurant, id: restaurant.id, in: Name.restaurants)
    }

    func save(_ visit: VisitDTO) async throws {
        try await put(visit, id: visit.id, in: Name.visits)
    }

    /// Saves several cafés in one transaction (used when the list order changes).
    func saveAll(_ restaurants: [RestaurantDTO]) async throws {
        guard !restaurants.isEmpty else { return }
        let transaction = database.transaction!(Name.restaurants, "readwrite").object!
        let store = transaction.objectStore!(Name.restaurants).object!
        for restaurant in restaurants {
            let json = String(decoding: try encoder.encode(restaurant), as: UTF8.self)
            _ = store.put!(json, restaurant.id.uuidString)
        }
        try await completion(of: transaction)
    }

    /// Deletes cafés together with all their visits, atomically.
    func deleteRestaurants(ids: [UUID], visitIDs: [UUID]) async throws {
        let transaction = database.transaction!([Name.restaurants, Name.visits], "readwrite").object!
        let restaurantStore = transaction.objectStore!(Name.restaurants).object!
        let visitStore = transaction.objectStore!(Name.visits).object!
        for id in ids { _ = restaurantStore.delete!(id.uuidString) }
        for id in visitIDs { _ = visitStore.delete!(id.uuidString) }
        try await completion(of: transaction)
    }

    func deleteVisit(id: UUID) async throws {
        let transaction = database.transaction!(Name.visits, "readwrite").object!
        let store = transaction.objectStore!(Name.visits).object!
        _ = store.delete!(id.uuidString)
        try await completion(of: transaction)
    }

    // MARK: - Helpers

    private func loadAll<T: Decodable>(from storeName: String) async throws -> [T] {
        let transaction = database.transaction!(storeName, "readonly").object!
        let request = transaction.objectStore!(storeName).object!.getAll!().object!
        let result = try await Self.result(of: request)
        guard let array = JSArray(result.object!) else { return [] }
        return array.compactMap { value in
            guard let json = value.string else { return nil }
            return try? decoder.decode(T.self, from: Data(json.utf8))
        }
    }

    private func put<T: Encodable>(_ value: T, id: UUID, in storeName: String) async throws {
        let json = String(decoding: try encoder.encode(value), as: UTF8.self)
        let transaction = database.transaction!(storeName, "readwrite").object!
        _ = transaction.objectStore!(storeName).object!.put!(json, id.uuidString)
        try await completion(of: transaction)
    }

    /// Awaits an `IDBRequest`.
    private static func result(of request: JSObject) async throws -> JSValue {
        try await withCheckedThrowingContinuation { continuation in
            request.onsuccess = .object(JSOneshotClosure { _ in
                continuation.resume(returning: request.result)
                return .undefined
            })
            request.onerror = .object(JSOneshotClosure { _ in
                continuation.resume(throwing: StoreError.requestFailed(request.error.object?.message.string ?? "unknown"))
                return .undefined
            })
        }
    }

    /// Awaits the commit of an `IDBTransaction`.
    private func completion(of transaction: JSObject) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            transaction.oncomplete = .object(JSOneshotClosure { _ in
                continuation.resume()
                return .undefined
            })
            transaction.onerror = .object(JSOneshotClosure { _ in
                continuation.resume(throwing: StoreError.requestFailed(transaction.error.object?.message.string ?? "unknown"))
                return .undefined
            })
        }
    }
}

enum StoreError: Error, CustomStringConvertible {
    case requestFailed(String)

    var description: String {
        switch self {
        case .requestFailed(let message): return "Storage error: \(message)"
        }
    }
}
