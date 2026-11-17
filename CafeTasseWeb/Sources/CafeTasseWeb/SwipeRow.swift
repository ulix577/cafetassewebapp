import JavaScriptKit

/// Wraps `content` in a row that reveals a Delete button when swiped to the left (touch or mouse).
/// When `canDelete` is false the row is returned without any swipe behaviour.
func swipeToDeleteRow(content: JSObject, canDelete: Bool, onDelete: @escaping () -> Void) -> JSObject {
    guard canDelete else {
        return el("div", "swipe-row locked", [content])
    }

    let revealWidth = 96.0
    let deleteButton = el("button", "swipe-delete", text: "Delete")
    let slide = el("div", "swipe-content", [content])
    let row = el("div", "swipe-row", [deleteButton, slide])

    var startX = 0.0
    var offset = 0.0
    var isOpen = false
    var isDragging = false

    func move(to value: Double, animated: Bool) {
        offset = value
        slide.setStyle("transition", animated ? "transform 0.2s ease" : "none")
        slide.setStyle("transform", "translateX(\(offset)px)")
    }

    slide.on("pointerdown") { event in
        isDragging = true
        startX = event.clientX.number ?? 0
        _ = slide.setPointerCapture!(event.pointerId)
    }
    slide.on("pointermove") { event in
        guard isDragging else { return }
        let delta = (event.clientX.number ?? 0) - startX
        let base = isOpen ? -revealWidth : 0
        move(to: min(0, max(-revealWidth, base + delta)), animated: false)
    }
    let finish: (JSObject) -> Void = { _ in
        guard isDragging else { return }
        isDragging = false
        isOpen = offset < -revealWidth / 2
        move(to: isOpen ? -revealWidth : 0, animated: true)
    }
    slide.on("pointerup", finish)
    slide.on("pointercancel", finish)

    deleteButton.on("click") { _ in onDelete() }
    return row
}
