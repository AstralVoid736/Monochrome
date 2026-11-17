import AppKit

final class UIBackend: GrayscaleBackend {
    var value: FilterState = .color
    var writes = 0
    func readState() throws -> FilterState { value }
    func writeGrayscale(_ enabled: Bool) throws { writes += 1; value = enabled ? .grayscale : .color }
}

@main
struct UITests {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let backend = UIBackend()
        let ui = StatusBarController(controller: GrayscaleController(backend: backend))
        defer { NSStatusBar.system.removeStatusItem(ui.statusItem) }
        func require(_ value: Bool, _ message: String) {
            guard value else { print("FAIL: \(message)"); exit(1) }
        }
        require(backend.writes == 0, "launch must never change the display")
        require(ui.menu.items.contains { $0.title == "Включить оттенки серого" }, "menu must expose the actual toggle")
        ui.statusItem.button?.performClick(nil)
        require(backend.value == .grayscale && backend.writes == 1, "native status-button action must toggle exactly once")
        require(ui.statusItem.button?.toolTip?.contains("чёрно-белый") == true, "tooltip must reflect the observed state")
        guard let index = ui.menu.items.firstIndex(where: { $0.title == "Вернуть цвета" }) else { print("FAIL: reverse action missing"); exit(1) }
        ui.menu.performActionForItem(at: index)
        require(backend.value == .color && backend.writes == 2, "native menu target/action must restore color")
        print("PASS: no startup write; native status-button and menu target/actions toggle both ways")
        print("Input coverage: AppKit programmatic control actions; not mouse/AX interaction")
    }
}
