import CafeTasseCore
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import JavaScriptKit

extension App {

    // MARK: - Café list

    func listScreen() -> JSObject {
        let addButton = el("button", "icon-button", text: "+")
        addButton.attr("aria-label", "Add café")
        addButton.on("click") { _ in self.navigate(to: .add) }

        let screen = el("main", "screen", [header(title: "Cafés", trailing: addButton)])

        let sorted = restaurants.sorted { $0.name.lowercased() < $1.name.lowercased() }
        guard !sorted.isEmpty else {
            _ = screen.appendChild!(el("p", "empty", text: "No cafés yet. Tap + to add the one you're in."))
            return screen
        }

        let list = el("div", "list")
        for restaurant in sorted {
            let restaurantVisits = visits(for: restaurant.id)
            let title = el("div", "row-title", text: restaurant.name)
            let subtitle = el("div", "row-subtitle", text: [restaurant.typ, restaurant.adress]
                .filter { !$0.isEmpty }.joined(separator: " · "))
            let info = restaurantVisits.isEmpty
                ? "No visits yet"
                : "\(restaurantVisits.count) visit\(restaurantVisits.count == 1 ? "" : "s")  \(stars(restaurantVisits.averageRating))"
            let meta = el("div", "row-meta", text: info)

            let row = el("button", "card", [title, subtitle, meta])
            row.on("click") { _ in self.navigate(to: .detail(restaurant.id)) }
            _ = list.appendChild!(row)
        }
        _ = screen.appendChild!(list)
        return screen
    }

    // MARK: - Add café

    func addScreen() -> JSObject {
        let nameInput = el("input")
        nameInput.attr("type", "text")
        nameInput.attr("placeholder", "Name")
        nameInput.attr("autocomplete", "off")

        let typeSelect = el("select")
        for type in RestaurantDTO.restaurantTypes {
            let option = el("option", text: type)
            option.attr("value", type)
            _ = typeSelect.appendChild!(option)
        }

        let addressInput = el("input")
        addressInput.attr("type", "text")
        addressInput.attr("placeholder", "Street, number, city")

        let locationCheckbox = el("input")
        locationCheckbox.attr("type", "checkbox")
        locationCheckbox.checked = .boolean(true)
        let locationLabel = el("label", "checkbox", [locationCheckbox,
            el("span", text: "I'm here now — save my location as the café's location")])

        // Location from the typed address (only on tap, see `geocode(address:)`).
        var foundPlace: GeocodedPlace?
        let lookupButton = el("button", "secondary", text: "Find location from address")
        let lookupResult = el("p", "hint")
        lookupButton.on("click") { _ in
            let address = trimmed(addressInput.value.string ?? "")
            guard !address.isEmpty else {
                showNotice("Please type an address first.", isError: true)
                return
            }
            lookupButton.disabled = .boolean(true)
            lookupButton.textContent = .string("Searching…")
            Task {
                do {
                    let place = try await geocode(address: address)
                    foundPlace = place
                    // The found address replaces "I'm here now" so the two sources don't compete.
                    locationCheckbox.checked = .boolean(false)
                    lookupResult.textContent = .string("Found: \(place.displayName)")
                } catch {
                    foundPlace = nil
                    lookupResult.textContent = .string("")
                    showNotice(describe(error), isError: true)
                }
                lookupButton.disabled = .boolean(false)
                lookupButton.textContent = .string("Find location from address")
            }
        }
        // A changed address makes an earlier result stale.
        addressInput.on("input") { _ in
            foundPlace = nil
            lookupResult.textContent = .string("")
        }
        let lookupNote = el("p", "hint",
            text: "The address is sent to OpenStreetMap (Nominatim) to find its position.")

        let saveButton = el("button", "primary", text: "Save café")
        saveButton.on("click") { _ in
            let name = trimmed(nameInput.value.string ?? "")
            guard !name.isEmpty else {
                showNotice("Please enter a name.", isError: true)
                return
            }
            let type = typeSelect.value.string ?? ""
            let address = addressInput.value.string ?? ""
            let wantsLocation = locationCheckbox.checked.boolean ?? false

            saveButton.disabled = .boolean(true)
            saveButton.textContent = .string(wantsLocation ? "Locating…" : "Saving…")
            Task {
                var restaurant = RestaurantDTO(typ: type, name: name, adress: address)
                if !wantsLocation, let place = foundPlace {
                    restaurant.latitude = place.coordinate.latitude
                    restaurant.longitude = place.coordinate.longitude
                }
                if wantsLocation {
                    do {
                        let position = try await currentPosition()
                        restaurant.latitude = position.latitude
                        restaurant.longitude = position.longitude
                    } catch {
                        showNotice("\(describe(error)) Saved without location.", isError: true)
                    }
                }
                await self.persist(restaurant)
                self.navigate(to: .detail(restaurant.id))
            }
        }

        let form = el("div", "form", [
            el("label", text: "Name"), nameInput,
            el("label", text: "Type"), typeSelect,
            el("label", text: "Address"), addressInput,
            lookupButton, lookupResult, lookupNote,
            locationLabel,
            saveButton
        ])
        return el("main", "screen", [header(title: "New café", back: .list), form])
    }

    // MARK: - Café detail

    func detailScreen(_ restaurant: RestaurantDTO) -> JSObject {
        let screen = el("main", "screen", [header(title: restaurant.name, back: .list)])

        // Info card
        let info = el("div", "info")
        func addRow(_ label: String, _ value: String) {
            guard !value.isEmpty else { return }
            _ = info.appendChild!(el("div", "info-row", [el("span", "label", text: label), el("span", text: value)]))
        }
        addRow("Type", restaurant.typ)
        addRow("Address", restaurant.adress)
        addRow("Location", restaurant.coordinate == nil ? "not set" : "saved")
        _ = screen.appendChild!(info)

        // Check-in
        let checkInButton = el("button", "primary", text: "Check in")
        checkInButton.on("click") { _ in self.startCheckIn(restaurant, button: checkInButton) }
        _ = screen.appendChild!(checkInButton)

        if restaurant.coordinate == nil {
            let setLocation = el("button", "secondary", text: "Use my current location as café location")
            setLocation.on("click") { _ in
                setLocation.disabled = .boolean(true)
                setLocation.textContent = .string("Locating…")
                Task {
                    do {
                        let position = try await currentPosition()
                        var updated = restaurant
                        updated.latitude = position.latitude
                        updated.longitude = position.longitude
                        await self.persist(updated)
                    } catch {
                        showNotice(describe(error), isError: true)
                    }
                    self.render()
                }
            }
            _ = screen.appendChild!(setLocation)

            if !trimmed(restaurant.adress).isEmpty {
                let lookup = el("button", "secondary", text: "Find location from address")
                lookup.on("click") { _ in
                    lookup.disabled = .boolean(true)
                    lookup.textContent = .string("Searching…")
                    Task {
                        do {
                            let place = try await geocode(address: restaurant.adress)
                            if confirmInBrowser("Found:\n\(place.displayName)\n\nUse this as the café's location?") {
                                var updated = restaurant
                                updated.latitude = place.coordinate.latitude
                                updated.longitude = place.coordinate.longitude
                                await self.persist(updated)
                            }
                        } catch {
                            showNotice(describe(error), isError: true)
                        }
                        self.render()
                    }
                }
                _ = screen.appendChild!(lookup)
            }
        }

        // Visits
        let restaurantVisits = visits(for: restaurant.id)
        let canDelete = VisitDeletionPolicy.canDeleteVisits(visitCount: restaurantVisits.count)
        _ = screen.appendChild!(el("h2", text: "Visits (\(restaurantVisits.count))"))
        if !canDelete {
            let needed = VisitDeletionPolicy.minimumVisitsForDeletion
            _ = screen.appendChild!(el("p", "hint",
                text: "Visits can be deleted by swiping once this café has \(needed) visits (\(restaurantVisits.count)/\(needed))."))
        }
        _ = screen.appendChild!(visitList(restaurantVisits, canDelete: canDelete, showRestaurantName: false))
        return screen
    }

    private func startCheckIn(_ restaurant: RestaurantDTO, button: JSObject) {
        button.disabled = .boolean(true)
        button.textContent = .string("Locating…")
        Task {
            let fix = try? await currentFix()
            let validation = policy.validate(
                restaurantCoordinate: restaurant.coordinate,
                userCoordinate: fix?.coordinate,
                existingVisitDates: visits(for: restaurant.id).map(\.date),
                now: Date(),
                calendar: browserCalendar()
            )
            if validation.isAllowed {
                draft = CheckInDraft()
                navigate(to: .checkIn(restaurant.id))
            } else {
                showNotice(message(for: validation, accuracy: fix?.accuracy), isError: true)
                render()
            }
        }
    }

    // MARK: - Check-in with photo

    func checkInScreen(_ restaurant: RestaurantDTO) -> JSObject {
        let preview = el("div", "photo-preview")
        func refreshPreview() {
            preview.clear()
            if let image = photoElement(draft.photoBase64, className: "photo") {
                let remove = el("button", "secondary", text: "Remove photo")
                remove.on("click") { _ in
                    self.draft.photoBase64 = nil
                    refreshPreview()
                }
                _ = preview.appendChild!(image)
                _ = preview.appendChild!(remove)
            } else {
                _ = preview.appendChild!(el("p", "hint", text: "Add a photo to remember your visit (optional)."))
            }
        }
        refreshPreview()

        // Live camera only: no file or gallery picker, so every photo is taken during the visit.
        let takePhoto = el("button", "secondary", text: "Take photo")
        takePhoto.on("click") { _ in
            takePhoto.disabled = .boolean(true)
            Task {
                do {
                    if let photo = try await captureLivePhoto() {
                        self.draft.photoBase64 = photo
                        refreshPreview()
                    }
                } catch {
                    showNotice(describe(error), isError: true)
                }
                takePhoto.disabled = .boolean(false)
            }
        }
        let photoButtons = el("div", "button-row", [takePhoto])

        // Rating
        let ratingRow = el("div", "rating")
        func refreshRating() {
            ratingRow.clear()
            for value in 1...5 {
                let star = el("button", value <= draft.rating ? "star on" : "star", text: value <= draft.rating ? "★" : "☆")
                star.attr("aria-label", "\(value) star\(value == 1 ? "" : "s")")
                star.on("click") { _ in
                    self.draft.rating = (self.draft.rating == value) ? 0 : value
                    refreshRating()
                }
                _ = ratingRow.appendChild!(star)
            }
        }
        refreshRating()

        let orderInput = el("input")
        orderInput.attr("type", "text")
        orderInput.attr("placeholder", "What did you order?")
        orderInput.value = .string(draft.orderNotes)
        orderInput.on("input") { _ in self.draft.orderNotes = orderInput.value.string ?? "" }

        let spentInput = el("input")
        spentInput.attr("type", "number")
        spentInput.attr("inputmode", "decimal")
        spentInput.attr("step", "0.01")
        spentInput.attr("min", "0")
        spentInput.attr("placeholder", "Amount spent (optional)")
        spentInput.value = .string(draft.spent)
        spentInput.on("input") { _ in self.draft.spent = spentInput.value.string ?? "" }

        let notesInput = el("textarea")
        notesInput.attr("rows", "3")
        notesInput.attr("placeholder", "Notes")
        notesInput.value = .string(draft.notes)
        notesInput.on("input") { _ in self.draft.notes = notesInput.value.string ?? "" }

        let save = el("button", "primary", text: "Save visit")
        save.on("click") { _ in
            save.disabled = .boolean(true)
            let visit = VisitDTO(
                restaurantID: restaurant.id,
                date: Date(),
                notes: self.draft.notes,
                rating: Double(self.draft.rating),
                photosTaken: self.draft.photoBase64 == nil ? 0 : 1,
                spentAmount: Double(String(self.draft.spent.map { $0 == "," ? "." : $0 })),
                orderNotes: self.draft.orderNotes,
                photoDataBase64: self.draft.photoBase64
            )
            Task {
                await self.persist(visit)
                self.draft = CheckInDraft()
                self.navigate(to: .detail(restaurant.id))
            }
        }

        let form = el("div", "form", [
            el("h2", text: "Photo"), preview, photoButtons,
            el("h2", text: "Rating"), ratingRow,
            el("h2", text: "Details"), orderInput, spentInput, notesInput,
            save
        ])
        return el("main", "screen", [header(title: "Check in", back: .detail(restaurant.id)), form])
    }

    // MARK: - Visit history

    func historyScreen() -> JSObject {
        let screen = el("main", "screen", [header(title: "History")])
        let all = visits.sorted { $0.date > $1.date }
        guard !all.isEmpty else {
            _ = screen.appendChild!(el("p", "empty", text: "No visits yet. Check in at a café to start your history."))
            return screen
        }
        let needed = VisitDeletionPolicy.minimumVisitsForDeletion
        _ = screen.appendChild!(el("p", "hint",
            text: "Show the shop owner your \(needed) visits, then swipe to reset while they watch. "
                + "Enjoy your bonus, and start collecting again!"))
        _ = screen.appendChild!(visitList(all, canDelete: nil, showRestaurantName: true))
        return screen
    }

    /// `canDelete == nil` means: decide per visit from the visit count of its café.
    private func visitList(_ list: [VisitDTO], canDelete: Bool?, showRestaurantName: Bool) -> JSObject {
        let container = el("div", "list")
        for visit in list {
            let allowed = canDelete
                ?? VisitDeletionPolicy.canDeleteVisits(visitCount: visits(for: visit.restaurantID).count)
            _ = container.appendChild!(swipeToDeleteRow(content: visitRow(visit, showRestaurantName: showRestaurantName),
                                                        canDelete: allowed) {
                self.deleteVisit(visit)
            })
        }
        return container
    }

    private func visitRow(_ visit: VisitDTO, showRestaurantName: Bool) -> JSObject {
        let text = el("div", "visit-text")
        if showRestaurantName {
            _ = text.appendChild!(el("div", "row-title", text: restaurant(visit.restaurantID)?.name ?? "Unknown café"))
        }
        _ = text.appendChild!(el("div", showRestaurantName ? "row-subtitle" : "row-title", text: formatDate(visit.date)))
        if visit.rating > 0 { _ = text.appendChild!(el("div", "row-meta", text: stars(visit.rating))) }
        if !visit.orderNotes.isEmpty { _ = text.appendChild!(el("div", "row-subtitle", text: "☕ \(visit.orderNotes)")) }
        if let spent = visit.spentAmount {
            let cents = Int((spent * 100).rounded())
            let amount = "\(cents / 100).\(cents % 100 < 10 ? "0" : "")\(cents % 100)"
            _ = text.appendChild!(el("div", "row-subtitle", text: "€\(amount)"))
        }
        if !visit.notes.isEmpty { _ = text.appendChild!(el("div", "row-subtitle", text: visit.notes)) }

        let row = el("div", "visit")
        if let thumbnail = photoElement(visit.photoDataBase64, className: "thumb") {
            _ = row.appendChild!(thumbnail)
        }
        _ = row.appendChild!(text)
        return row
    }
}
