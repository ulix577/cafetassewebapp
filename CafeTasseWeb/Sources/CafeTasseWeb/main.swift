import JavaScriptEventLoop
import JavaScriptKit

JavaScriptEventLoop.installGlobalExecutor()

Task {
    guard let root = document.getElementById!("app").object else { return }
    do {
        let store = try await Store.open()
        let app = App(root: root, store: store)
        await app.start()
    } catch {
        root.textContent = .string("Could not open local storage: \(describe(error))")
    }
}
