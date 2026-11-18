#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import JavaScriptKit

let document = JSObject.global.document.object!

/// Creates an element with an optional class, text and children.
func el(_ tag: String, _ className: String = "", text: String? = nil, _ children: [JSObject] = []) -> JSObject {
    let node = document.createElement!(tag).object!
    if !className.isEmpty { node.className = .string(className) }
    if let text { node.textContent = .string(text) }
    for child in children { _ = node.appendChild!(child) }
    return node
}

extension JSObject {
    func on(_ event: String, _ handler: @escaping (JSObject) -> Void) {
        _ = self.addEventListener!(event, JSClosure { args in
            handler(args[0].object!)
            return .undefined
        })
    }

    func attr(_ name: String, _ value: String) {
        _ = self.setAttribute!(name, value)
    }

    func setStyle(_ property: String, _ value: String) {
        _ = self.style.object!.setProperty!(property, value)
    }

    func clear() {
        self.innerHTML = .string("")
    }
}

/// Runs `body` once after `milliseconds`.
func after(milliseconds: Double, _ body: @escaping () -> Void) {
    _ = JSObject.global.setTimeout!(JSOneshotClosure { _ in
        body()
        return .undefined
    }, milliseconds)
}

/// Formats a date using the browser's locale and time zone.
func formatDate(_ date: Date) -> String {
    let jsDate = JSObject.global.Date.function!.new(date.timeIntervalSince1970 * 1000)
    return jsDate.toLocaleString!().string ?? ""
}

/// A calendar in the browser's time zone. Foundation on WebAssembly has no time zone data,
/// so "today" would otherwise be computed in UTC.
func browserCalendar() -> Calendar {
    let jsDate = JSObject.global.Date.function!.new()
    let offsetMinutes = jsDate.getTimezoneOffset!().number ?? 0
    var calendar = Calendar(identifier: .gregorian)
    if let zone = TimeZone(secondsFromGMT: -Int(offsetMinutes) * 60) {
        calendar.timeZone = zone
    }
    return calendar
}

func confirmInBrowser(_ message: String) -> Bool {
    JSObject.global.confirm!(message).boolean ?? false
}

/// Small transient message at the bottom of the screen.
func showNotice(_ message: String, isError: Bool = false) {
    let toast = el("div", isError ? "toast error" : "toast", text: message)
    _ = document.body.object!.appendChild!(toast)
    // Roughly 60 ms per character so long messages stay readable (minimum 4 s).
    after(milliseconds: max(4000, Double(message.count) * 60)) { _ = toast.remove!() }
}

/// Error text for the UI. `localizedDescription` lives in full Foundation, which this target avoids.
func describe(_ error: Error) -> String {
    (error as? CustomStringConvertible)?.description ?? "\(error)"
}

/// Strips leading and trailing whitespace (`trimmingCharacters` is not in FoundationEssentials).
func trimmed(_ text: String) -> String {
    var scalars = Substring(text)
    while let first = scalars.first, first.isWhitespace { scalars.removeFirst() }
    while let last = scalars.last, last.isWhitespace { scalars.removeLast() }
    return String(scalars)
}
