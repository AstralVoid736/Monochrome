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
        func require(_ value: Bool, _ message: String) {
            guard value else { print("FAIL: \(message)"); exit(1) }
        }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        guard let russian = Bundle(url: root.appendingPathComponent("Resources/ru.lproj")) else {
            print("FAIL: Russian localization resource is missing"); exit(1)
        }
        for (locale, bundle, enable, restore, quit, tooltip) in [
            ("en", Bundle.main, "Enable Grayscale", "Restore Color", "Quit Monochrome", "grayscale"),
            ("ru", russian, "Включить оттенки серого", "Вернуть цвета", "Выйти из Monochrome", "чёрно-белый")
        ] {
            let backend = UIBackend()
            let ui = StatusBarController(controller: GrayscaleController(backend: backend), strings: bundle)
            defer { NSStatusBar.system.removeStatusItem(ui.statusItem) }
            require(backend.writes == 0, "launch must never change the display")
            require(ui.menu.items.contains { $0.title == enable }, "menu must localize the toggle: \(locale)")
            require(ui.menu.items.contains { $0.title == quit && $0.action != nil }, "menu must expose a localized Quit action: \(locale)")
            ui.statusItem.button?.performClick(nil)
            require(backend.value == .grayscale && backend.writes == 1, "native status-button action must toggle exactly once")
            require(ui.statusItem.button?.toolTip?.contains(tooltip) == true, "tooltip must reflect the observed state: \(locale)")
            guard let index = ui.menu.items.firstIndex(where: { $0.title == restore }) else { print("FAIL: reverse action missing"); exit(1) }
            ui.menu.performActionForItem(at: index)
            require(backend.value == .color && backend.writes == 2, "native menu target/action must restore color")
            print("PASS: \(locale) interface; native status-button and menu actions; no startup write")
        }
        print("Input coverage: AppKit programmatic control actions; not mouse/AX interaction")
    }
}
