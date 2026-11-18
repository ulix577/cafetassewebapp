import CafeTasseCore
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import JavaScriptKit

enum BrowserError: Error, CustomStringConvertible {
    case geolocationUnavailable
    case locationDenied(String)
    case imageFailed
    case addressNotFound
    case geocodingFailed(String)

    var description: String {
        switch self {
        case .geolocationUnavailable: return "This browser has no location support."
        case .locationDenied(let reason): return "Location unavailable: \(reason)"
        case .imageFailed: return "The photo could not be read."
        case .addressNotFound: return "No place found for this address. Check the spelling or add the city."
        case .geocodingFailed(let reason): return "Address lookup failed: \(reason)"
        }
    }
}

/// One-shot position request through the browser Geolocation API (needs HTTPS or localhost).
func currentPosition() async throws -> Coordinate {
    try await withCheckedThrowingContinuation { continuation in
        guard let geolocation = JSObject.global.navigator.object?.geolocation.object else {
            continuation.resume(throwing: BrowserError.geolocationUnavailable)
            return
        }
        let options = JSObject.global.Object.function!.new()
        options.enableHighAccuracy = .boolean(true)
        options.timeout = .number(15_000)
        options.maximumAge = .number(0)

        let onSuccess = JSOneshotClosure { args in
            let coords = args[0].object!.coords.object!
            continuation.resume(returning: Coordinate(
                latitude: coords.latitude.number ?? 0,
                longitude: coords.longitude.number ?? 0
            ))
            return .undefined
        }
        let onError = JSOneshotClosure { args in
            let message = args[0].object?.message.string ?? "unknown error"
            continuation.resume(throwing: BrowserError.locationDenied(message))
            return .undefined
        }
        _ = geolocation.getCurrentPosition!(onSuccess, onError, options)
    }
}

/// Reads an image `File`, scales it so the longer side is at most `maxSide` pixels and returns a
/// base64-encoded JPEG (without the data-URL prefix), matching `Visit.photoDataBase64` on iOS.
func resizedJPEGBase64(from file: JSObject, maxSide: Double = 1280, quality: Double = 0.8) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
        let urlObject = JSObject.global.URL.object!
        let objectURL = urlObject.createObjectURL!(file)
        let image = JSObject.global.Image.function!.new()

        image.onload = .object(JSOneshotClosure { _ in
            let width = image.naturalWidth.number ?? 0
            let height = image.naturalHeight.number ?? 0
            let scale = min(1, maxSide / max(width, height, 1))

            let canvas = document.createElement!("canvas").object!
            canvas.width = .number((width * scale).rounded())
            canvas.height = .number((height * scale).rounded())
            let context = canvas.getContext!("2d").object!
            _ = context.drawImage!(image, 0, 0, canvas.width, canvas.height)

            let dataURL = canvas.toDataURL!("image/jpeg", quality).string ?? ""
            _ = urlObject.revokeObjectURL!(objectURL)

            // dataURL looks like "data:image/jpeg;base64,<payload>"
            if let comma = dataURL.firstIndex(of: ",") {
                continuation.resume(returning: String(dataURL[dataURL.index(after: comma)...]))
            } else {
                continuation.resume(throwing: BrowserError.imageFailed)
            }
            return .undefined
        })
        image.onerror = .object(JSOneshotClosure { _ in
            _ = urlObject.revokeObjectURL!(objectURL)
            continuation.resume(throwing: BrowserError.imageFailed)
            return .undefined
        })
        image.src = objectURL
    }
}

/// Builds a hidden `<input type="file">` and calls `onFile` with the chosen image.
/// With `useCamera` phones open the camera directly; desktops show the file picker.
func makeImageInput(useCamera: Bool, onFile: @escaping (JSObject) -> Void) -> JSObject {
    let input = el("input")
    input.attr("type", "file")
    input.attr("accept", "image/*")
    if useCamera { input.attr("capture", "environment") }
    input.setStyle("display", "none")
    input.on("change") { _ in
        if let file = input.files.object?[0].object {
            onFile(file)
        }
        input.value = .string("")
    }
    return input
}

/// Looks an address up with OpenStreetMap's Nominatim service (https://operations.osmfoundation.org/policies/nominatim/).
/// Only call this from a user action (button tap): the policy allows about one request per second
/// and forbids automatic or bulk lookups. The address is sent to that service.
func geocode(address: String) async throws -> GeocodedPlace {
    let query = JSObject.global.encodeURIComponent!(address).string ?? ""
    let url = "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&q=\(query)"

    let text: String
    do {
        let response = try await JSPromise(JSObject.global.fetch!(url).object!)!.value.object!
        guard response.ok.boolean == true else {
            throw BrowserError.geocodingFailed("server answered \(Int(response.status.number ?? 0))")
        }
        text = try await JSPromise(response.text!().object!)!.value.string ?? ""
    } catch let error as BrowserError {
        throw error
    } catch {
        throw BrowserError.geocodingFailed("no connection to the lookup service")
    }

    guard let place = GeocodingResponse.firstPlace(in: Data(text.utf8)) else {
        throw BrowserError.addressNotFound
    }
    return place
}
