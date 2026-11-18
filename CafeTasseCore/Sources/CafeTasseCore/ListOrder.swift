/// Reordering of a list by moving a selection of items one step up or down (the "Up" / "Down" buttons).
public enum ListOrder {
    /// Moves every selected item one position towards the start. A selected item stays put when the
    /// item above it is also selected, so a selected block keeps its internal order and stops at the top.
    public static func moveUp<ID: Hashable>(_ selected: Set<ID>, in items: [ID]) -> [ID] {
        var result = items
        guard result.count > 1 else { return result }
        for index in 1..<result.count {
            if selected.contains(result[index]) && !selected.contains(result[index - 1]) {
                result.swapAt(index, index - 1)
            }
        }
        return result
    }

    /// Moves every selected item one position towards the end (mirror image of `moveUp`).
    public static func moveDown<ID: Hashable>(_ selected: Set<ID>, in items: [ID]) -> [ID] {
        var result = items
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 2, through: 0, by: -1) {
            if selected.contains(result[index]) && !selected.contains(result[index + 1]) {
                result.swapAt(index, index + 1)
            }
        }
        return result
    }
}
