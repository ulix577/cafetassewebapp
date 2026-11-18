import CafeTasseCore
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import JavaScriptKit

/// Maximum distance in meters between guest and café for a check-in. Same as the iOS default.
/// Browser GPS is often less precise than this (phones outdoors: roughly 5-20 m, laptops: much worse),
/// so guests may be told they are "too far away" while standing in the café; raise it if that happens.
let webCheckInRadius = 10.0

enum Route: Equatable {
    case list
    case add
    case detail(UUID)
    case checkIn(UUID)
    case history
}

/// Values entered on the check-in screen. Kept here so re-rendering does not lose them.
struct CheckInDraft {
    var photoBase64: String?
    var rating = 0
    var orderNotes = ""
    var spent = ""
    var notes = ""
}

final class App {
    let root: JSObject
    let store: Store
    let policy = CheckInPolicy(radius: webCheckInRadius)

    var restaurants: [RestaurantDTO] = []
    var visits: [VisitDTO] = []
    var route: Route = .list
    var draft = CheckInDraft()
    /// Café list "Edit" mode: rows become selectable for moving and deleting.
    var isEditingList = false
    var selectedRestaurantIDs: Set<UUID> = []

    init(root: JSObject, store: Store) {
        self.root = root
        self.store = store
    }

    func start() async {
        do {
            restaurants = try await store.loadRestaurants()
            visits = try await store.loadVisits()
        } catch {
            showNotice(describe(error), isError: true)
        }
        await normalizeOrder()
        render()
    }

    func navigate(to route: Route) {
        if route != .list {
            isEditingList = false
            selectedRestaurantIDs = []
        }
        self.route = route
        render()
        _ = JSObject.global.window.object!.scrollTo!(0, 0)
    }

    // MARK: - Data access

    func restaurant(_ id: UUID) -> RestaurantDTO? {
        restaurants.first { $0.id == id }
    }

    /// Cafés in the user's order. Cafés without a stored position (data from before ordering existed)
    /// come last, alphabetically.
    func orderedRestaurants() -> [RestaurantDTO] {
        restaurants.sorted {
            ($0.sortOrder ?? Int.max, $0.name.lowercased()) < ($1.sortOrder ?? Int.max, $1.name.lowercased())
        }
    }

    /// Gives every café a stored position, keeping the order the list currently shows.
    private func normalizeOrder() async {
        guard restaurants.contains(where: { $0.sortOrder == nil }) else { return }
        await saveChanged(setOrder(orderedRestaurants().map(\.id)))
    }

    /// Updates `sortOrder` in memory to match `ids`; returns the cafés whose position changed.
    private func setOrder(_ ids: [UUID]) -> [RestaurantDTO] {
        var changed: [RestaurantDTO] = []
        for (position, id) in ids.enumerated() {
            guard let index = restaurants.firstIndex(where: { $0.id == id }),
                  restaurants[index].sortOrder != position else { continue }
            restaurants[index].sortOrder = position
            changed.append(restaurants[index])
        }
        return changed
    }

    private func saveChanged(_ changed: [RestaurantDTO]) async {
        do {
            try await store.saveAll(changed)
        } catch {
            showNotice(describe(error), isError: true)
        }
    }

    /// Moves the selected cafés one step up or down and stores the new order.
    func moveSelectedRestaurants(up: Bool) {
        let ids = orderedRestaurants().map(\.id)
        let moved = up
            ? ListOrder.moveUp(selectedRestaurantIDs, in: ids)
            : ListOrder.moveDown(selectedRestaurantIDs, in: ids)
        guard moved != ids else { return }
        let changed = setOrder(moved)
        render()
        Task { await saveChanged(changed) }
    }

    /// Deletes the selected cafés and, with them, all of their visits.
    func deleteSelectedRestaurants() {
        let selected = selectedRestaurantIDs
        guard !selected.isEmpty else { return }
        let visitIDs = visits.filter { selected.contains($0.restaurantID) }.map(\.id)
        let cafes = selected.count == 1 ? "1 café" : "\(selected.count) cafés"
        let visitText = visitIDs.count == 1 ? "its 1 visit" : "their \(visitIDs.count) visits"
        guard confirmInBrowser("Delete \(cafes) and \(visitText)? This cannot be undone.") else { return }
        Task {
            do {
                try await store.deleteRestaurants(ids: Array(selected), visitIDs: visitIDs)
                restaurants.removeAll { selected.contains($0.id) }
                visits.removeAll { selected.contains($0.restaurantID) }
                selectedRestaurantIDs = []
                isEditingList = false
                // Close the gaps so positions stay 0, 1, 2, ...
                await saveChanged(setOrder(orderedRestaurants().map(\.id)))
            } catch {
                showNotice(describe(error), isError: true)
            }
            render()
        }
    }

    func visits(for restaurantID: UUID) -> [VisitDTO] {
        visits.filter { $0.restaurantID == restaurantID }.sorted { $0.date > $1.date }
    }

    func persist(_ restaurant: RestaurantDTO) async {
        var restaurant = restaurant
        let isNew = !restaurants.contains { $0.id == restaurant.id }
        if isNew && restaurant.sortOrder == nil {
            // New cafés go to the end of the list.
            restaurant.sortOrder = (restaurants.compactMap(\.sortOrder).max() ?? -1) + 1
        }
        do {
            try await store.save(restaurant)
            if let index = restaurants.firstIndex(where: { $0.id == restaurant.id }) {
                restaurants[index] = restaurant
            } else {
                restaurants.append(restaurant)
            }
        } catch {
            showNotice(describe(error), isError: true)
        }
    }

    func persist(_ visit: VisitDTO) async {
        do {
            try await store.save(visit)
            visits.append(visit)
        } catch {
            showNotice(describe(error), isError: true)
        }
    }

    /// Deletes a visit, enforcing the "at least 10 visits" rule again at the point of action.
    func deleteVisit(_ visit: VisitDTO) {
        guard VisitDeletionPolicy.canDeleteVisits(visitCount: visits(for: visit.restaurantID).count) else {
            showNotice("Visits can be deleted once a café has \(VisitDeletionPolicy.minimumVisitsForDeletion) visits.", isError: true)
            return
        }
        guard confirmInBrowser("Delete this visit?") else {
            render()
            return
        }
        Task {
            do {
                try await store.deleteVisit(id: visit.id)
                visits.removeAll { $0.id == visit.id }
            } catch {
                showNotice(describe(error), isError: true)
            }
            render()
        }
    }

    // MARK: - Rendering

    func render() {
        root.clear()
        let screen: JSObject
        switch route {
        case .list: screen = listScreen()
        case .add: screen = addScreen()
        case .detail(let id): screen = restaurant(id).map(detailScreen) ?? listScreen()
        case .checkIn(let id): screen = restaurant(id).map(checkInScreen) ?? listScreen()
        case .history: screen = historyScreen()
        }
        _ = root.appendChild!(screen)
        _ = root.appendChild!(tabBar())
    }

    private func tabBar() -> JSObject {
        let onHistory = route == .history
        let cafes = el("button", onHistory ? "tab" : "tab active", text: "Cafés")
        let history = el("button", onHistory ? "tab active" : "tab", text: "History")
        cafes.on("click") { _ in self.navigate(to: .list) }
        history.on("click") { _ in self.navigate(to: .history) }
        return el("nav", "tabbar", [cafes, history])
    }

    // MARK: - Shared view pieces

    func header(title: String, back: Route? = nil, trailing: JSObject? = nil) -> JSObject {
        let bar = el("header", "header")
        if let back {
            let button = el("button", "link", text: "‹ Back")
            button.on("click") { _ in self.navigate(to: back) }
            _ = bar.appendChild!(button)
        }
        _ = bar.appendChild!(el("h1", text: title))
        if let trailing { _ = bar.appendChild!(trailing) }
        return bar
    }

    func stars(_ rating: Double) -> String {
        let filled = Int(rating.rounded())
        guard filled > 0 else { return "" }
        return String(repeating: "★", count: min(filled, 5)) + String(repeating: "☆", count: max(0, 5 - filled))
    }

    func photoElement(_ base64: String?, className: String) -> JSObject? {
        guard let base64 else { return nil }
        let image = el("img", className)
        image.attr("src", "data:image/jpeg;base64,\(base64)")
        image.attr("alt", "Visit photo")
        return image
    }

    func message(for validation: CheckInValidation, accuracy: Double? = nil) -> String {
        switch validation {
        case .allowed:
            return "Ready to check in!"
        case .alreadyCheckedInToday(let date):
            return "Already checked in today at \(formatDate(date))."
        case .tooFarAway(let distance):
            var text = "You're \(formatDistance(distance)) away. Get closer to check in (max \(Int(policy.radius)) m)."
            if policy.isAccuracyTooLow(accuracy), let accuracy {
                text += " Your GPS is only accurate to about ±\(Int(accuracy.rounded())) m, so this may be a weak signal. "
                    + "Try near a window or outside, then check in again."
            }
            return text
        case .noLocation:
            return "Location unavailable. Allow location access to check in."
        case .noRestaurantCoordinates:
            return "This café has no saved location yet. Set it from the café page while you are there."
        }
    }
}
