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
    case cameraUnavailable
    case cameraDenied
    case noCamera
    case addressNotFound
    case geocodingFailed(String)

    var description: String {
        switch self {
        case .geolocationUnavailable: return "This browser has no location support."
        case .locationDenied(let reason): return "Location unavailable: \(reason)"
        case .cameraUnavailable: return "This browser cannot open the camera. Open the page in Chrome (Android) or Safari (iPhone)."
        case .cameraDenied: return "Camera access was denied. Allow the camera for this site in the browser settings, then try again."
        case .noCamera: return "No camera found on this device."
        case .addressNotFound: return "No place found for this address. Check the spelling or add the city."
        case .geocodingFailed(let reason): return "Address lookup failed: \(reason)"
        }
    }
}

/// A position fix with the error radius the device reports for it.
struct UserPosition {
    var coordinate: Coordinate
    /// 68 % confidence radius in meters (`GeolocationCoordinates.accuracy`).
    var accuracy: Double?
}

/// One-shot position request through the browser Geolocation API (needs HTTPS or localhost).
func currentPosition() async throws -> Coordinate {
    try await currentFix().coordinate
}

func currentFix() async throws -> UserPosition {
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
            continuation.resume(returning: UserPosition(
                coordinate: Coordinate(
                    latitude: coords.latitude.number ?? 0,
                    longitude: coords.longitude.number ?? 0
                ),
                accuracy: coords.accuracy.number
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

/// Opens a full-screen live camera view and returns the captured photo as a base64-encoded JPEG
/// (without data-URL prefix), scaled so the longer side is at most `maxSide` pixels. Returns nil if the
/// user cancels. There is deliberately no file or gallery fallback: the photo must be taken right now.
/// Needs HTTPS or localhost plus camera permission.
func captureLivePhoto(maxSide: Double = 1280, quality: Double = 0.8) async throws -> String? {
    guard let mediaDevices = JSObject.global.navigator.object?.mediaDevices.object else {
        throw BrowserError.cameraUnavailable
    }
    let constraints = JSObject.global.JSON.object!.parse!(
        #"{"video":{"facingMode":{"ideal":"environment"}},"audio":false}"#)

    let stream: JSObject
    do {
        stream = try await JSPromise(mediaDevices.getUserMedia!(constraints).object!)!.value.object!
    } catch {
        switch error.thrownValue.object?.name.string {
        case "NotFoundError", "OverconstrainedError": throw BrowserError.noCamera
        default: throw BrowserError.cameraDenied
        }
    }

    let video = el("video", "camera-video")
    video.attr("playsinline", "")
    video.attr("autoplay", "")
    video.muted = .boolean(true)
    video.srcObject = .object(stream)
    _ = video.play!()

    let shutter = el("button", "shutter")
    shutter.attr("aria-label", "Take photo")
    let cancel = el("button", "camera-cancel", text: "Cancel")
    let controls = el("div", "camera-controls", [cancel, shutter, el("span", "camera-spacer")])
    let overlay = el("div", "camera-overlay", [video, controls])
    _ = document.body.object!.appendChild!(overlay)

    return await withCheckedContinuation { continuation in
        var isFinished = false
        func finish(_ result: String?) {
            guard !isFinished else { return }
            isFinished = true
            if let tracks = JSArray(stream.getTracks!().object!) {
                for track in tracks { _ = track.object?.stop!() }
            }
            _ = overlay.remove!()
            continuation.resume(returning: result)
        }

        cancel.on("click") { _ in finish(nil) }
        shutter.on("click") { _ in
            let width = video.videoWidth.number ?? 0
            let height = video.videoHeight.number ?? 0
            guard width > 0, height > 0 else { return }   // camera not ready yet

            let scale = min(1, maxSide / max(width, height))
            let canvas = document.createElement!("canvas").object!
            canvas.width = .number((width * scale).rounded())
            canvas.height = .number((height * scale).rounded())
            _ = canvas.getContext!("2d").object!.drawImage!(video, 0, 0, canvas.width, canvas.height)

            // dataURL looks like "data:image/jpeg;base64,<payload>"
            let dataURL = canvas.toDataURL!("image/jpeg", quality).string ?? ""
            if let comma = dataURL.firstIndex(of: ",") {
                finish(String(dataURL[dataURL.index(after: comma)...]))
            } else {
                finish(nil)
            }
        }
    }
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
