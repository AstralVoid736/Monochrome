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
        for (locale, bundle, enable, restore, quit, tooltip, shortcutTitle, conflict) in [
            ("en", Bundle.main, "Enable Grayscale", "Restore Color", "Quit Monochrome", "grayscale", "Keyboard Shortcut", "Shortcut in use"),
            ("ru", russian, "Включить оттенки серого", "Вернуть цвета", "Выйти из Monochrome", "чёрно-белый", "Горячая клавиша", "Сочетание занято")
        ] {
            let backend = UIBackend()
            let suite = "Monochrome.UITests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let hotKey = HotKeyController(defaults: defaults) { choice, _ in
                if choice == .three { throw HotKeyError.occupied }
                return {}
            }
            let ui = StatusBarController(controller: GrayscaleController(backend: backend), strings: bundle, hotKey: hotKey)
            defer { NSStatusBar.system.removeStatusItem(ui.statusItem) }
            hotKey.onToggle = { [weak ui] in ui?.toggleFromHotKey() }
            hotKey.start()
            ui.menuWillOpen(ui.menu)
            require(backend.writes == 0, "launch must never change the display")
            require(ui.menu.items.contains { $0.title == enable }, "menu must localize the toggle: \(locale)")
            require(ui.menu.items.contains { $0.title == quit && $0.action != nil }, "menu must expose a localized Quit action: \(locale)")
            ui.statusItem.button?.performClick(nil)
            require(backend.value == .grayscale && backend.writes == 1, "native status-button action must toggle exactly once")
            require(ui.statusItem.button?.toolTip?.contains(tooltip) == true, "tooltip must reflect the observed state: \(locale)")
            guard let index = ui.menu.items.firstIndex(where: { $0.title == restore }) else { print("FAIL: reverse action missing"); exit(1) }
            ui.menu.performActionForItem(at: index)
            require(backend.value == .color && backend.writes == 2, "native menu target/action must restore color")
            guard let shortcuts = ui.menu.items.first(where: { $0.title == shortcutTitle })?.submenu else {
                print("FAIL: shortcut chooser missing: \(locale)"); exit(1)
            }
            require(shortcuts.item(at: 2)?.state == .on, "default shortcut must be checked: \(locale)")
            shortcuts.performActionForItem(at: 4)
            require(shortcuts.item(at: 0)?.title.contains(conflict) == true && shortcuts.item(at: 2)?.state == .on,
                    "conflict must be shown without moving the check mark: \(locale)")
            shortcuts.performActionForItem(at: 3)
            require(shortcuts.item(at: 3)?.state == .on && hotKey.active == .two, "menu must select a replacement: \(locale)")
            require(hotKey.receiveRelease(3) && backend.value == .grayscale && backend.writes == 3,
                    "shortcut uses the same display controller: \(locale)")
            shortcuts.performActionForItem(at: 5)
            require(shortcuts.item(at: 5)?.state == .on && !hotKey.receiveRelease(3), "off disables the shortcut: \(locale)")
            backend.value = .otherFilter(4)
            ui.toggleFromHotKey()
            require(backend.value == .otherFilter(4) && backend.writes == 3, "hotkey cannot replace another filter")
            print("PASS: \(locale) interface; native status-button and menu actions; no startup write")
        }
        print("Input coverage: AppKit programmatic control actions; not mouse/AX interaction")
    }
}
