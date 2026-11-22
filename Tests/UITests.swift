import AppKit
import ServiceManagement

final class UIBackend: GrayscaleBackend {
    var value: FilterState = .color
    var writes = 0
    func readState() throws -> FilterState { value }
    func writeGrayscale(_ enabled: Bool) throws { writes += 1; value = enabled ? .grayscale : .color }
}

@MainActor
final class TestLoginItem: LoginItemService {
    enum Rejected: Error { case yes }
    var status: SMAppService.Status = .notRegistered
    var registeredStatus: SMAppService.Status = .enabled
    var reject = false
    private(set) var registrations = 0
    private(set) var removals = 0
    private(set) var settingsOpens = 0

    func register() throws {
        registrations += 1
        if reject { throw Rejected.yes }
        status = registeredStatus
    }
    func unregister() throws {
        removals += 1
        if reject { throw Rejected.yes }
        status = .notRegistered
    }
    func openSettings() { settingsOpens += 1 }
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
            let loginItem = TestLoginItem()
            let ui = StatusBarController(controller: GrayscaleController(backend: backend), strings: bundle, hotKey: hotKey,
                                         loginItem: loginItem)
            defer { NSStatusBar.system.removeStatusItem(ui.statusItem) }
            hotKey.onToggle = { [weak ui] in ui?.toggleFromHotKey() }
            hotKey.start()
            ui.menu.delegate?.menuNeedsUpdate?(ui.menu)
            require(backend.writes == 0, "launch must never change the display")
            let settingsTitle = locale == "ru" ? "Настройки" : "Settings"
            guard let settingsItem = ui.menu.items.first(where: { $0.title == settingsTitle }),
                  settingsItem.isEnabled, let settings = settingsItem.submenu else {
                print("FAIL: compact menu must have an enabled Settings submenu: \(locale)"); exit(1)
            }
            let loginTitle = locale == "ru" ? "Запускать при входе" : "Launch at Login"
            let start = locale == "ru" ? "Оттенки серого на 25 минут" : "Grayscale for 25 Minutes"
            let about = locale == "ru" ? "О Monochrome…" : "About Monochrome…"
            let visibleRows = ui.menu.items.filter { !$0.isHidden && !$0.isSeparatorItem }.map(\.title)
            require(visibleRows == [enable, start, settingsTitle, about, quit], "top-level menu keeps just the two quick actions, settings, about, and quit: \(locale)")
            settings.delegate?.menuNeedsUpdate?(settings)
            guard let loginIndex = settings.items.firstIndex(where: { $0.title == loginTitle && $0.action != nil }) else {
                print("FAIL: settings must expose the launch-at-login action: \(locale)"); exit(1)
            }
            let loginAction = settings.items[loginIndex]
            require(loginAction.isEnabled && loginAction.state == .off && loginItem.registrations == 0 && loginItem.removals == 0,
                    "launch and first menu open do not register the app or pretend it is registered")
            settings.performActionForItem(at: loginIndex)
            require(loginItem.registrations == 1 && loginAction.state == .on, "a menu action registers and reads back enabled status")
            let failure = locale == "ru" ? "Не удалось изменить автозапуск" : "Could Not Change Launch at Login"
            loginItem.reject = true
            settings.performActionForItem(at: loginIndex)
            require(loginItem.removals == 1 && loginAction.state == .on && settings.items.contains { $0.title == failure && !$0.isHidden },
                    "failure to disable leaves a check mark and a localized error")
            loginItem.reject = false
            settings.performActionForItem(at: loginIndex)
            require(loginItem.removals == 2 && loginAction.state == .off && !settings.items.contains { $0.title == failure && !$0.isHidden },
                    "an explicit retry can disable login launch and clear the error")
            loginItem.registeredStatus = .requiresApproval
            settings.performActionForItem(at: loginIndex)
            let approval = locale == "ru" ? "Автозапуск — открыть системные настройки…" : "Launch at Login — Review in System Settings…"
            require(loginItem.registrations == 2 && loginItem.settingsOpens == 0 && loginAction.state == .mixed && loginAction.title == approval,
                    "pending approval shows a localized route to Settings instead of claiming success")
            settings.performActionForItem(at: loginIndex)
            require(loginItem.settingsOpens == 1 && loginItem.registrations == 2 && loginItem.removals == 2,
                    "review action only opens Settings and never overrides the OS decision")
            loginItem.status = .enabled
            settings.delegate?.menuNeedsUpdate?(settings)
            require(loginAction.state == .on && loginAction.title == loginTitle, "opening Settings reads the system change")
            loginItem.status = .notFound
            ui.menu.delegate?.menuNeedsUpdate?(ui.menu)
            require(!loginAction.isEnabled && loginAction.state == .off, "unavailable service must not offer a working toggle")
            require(backend.writes == 0, "login options do not change the display")
            require(ui.menu.items.contains { $0.title == enable }, "menu must localize the toggle: \(locale)")
            require(ui.menu.items.contains { $0.title == quit && $0.action != nil }, "menu must expose a localized Quit action: \(locale)")
            ui.statusItem.button?.performClick(nil)
            require(backend.value == .grayscale && backend.writes == 1, "native status-button action must toggle exactly once")
            require(ui.statusItem.button?.toolTip?.contains(tooltip) == true, "tooltip must reflect the observed state: \(locale)")
            guard let index = ui.menu.items.firstIndex(where: { $0.title == restore }) else { print("FAIL: reverse action missing"); exit(1) }
            ui.menu.performActionForItem(at: index)
            require(backend.value == .color && backend.writes == 2, "native menu target/action must restore color")
            guard let shortcuts = settings.items.first(where: { $0.title == shortcutTitle })?.submenu else {
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
            let end = locale == "ru" ? "Завершить таймер и вернуть цвета" : "End Timer and Restore Color"
            guard let timerIndex = ui.menu.items.firstIndex(where: { $0.title == start }) else {
                print("FAIL: timer action missing: \(locale)"); exit(1)
            }
            require(ui.menu.item(at: timerIndex)?.isEnabled == false, "timer cannot start over another filter")
            backend.value = .color
            ui.menu.delegate?.menuNeedsUpdate?(ui.menu)
            ui.menu.performActionForItem(at: timerIndex)
            require(backend.value == .grayscale && ui.menu.item(at: timerIndex)?.title == end, "localized timer action starts the mode")
            ui.menu.performActionForItem(at: timerIndex)
            require(backend.value == .color && ui.menu.item(at: timerIndex)?.title == start, "ending the timer returns the color and restores the menu item")
            ui.menu.performActionForItem(at: timerIndex)
            ui.toggleFromHotKey()
            require(backend.value == .color && ui.menu.item(at: timerIndex)?.title == start, "shortcut cancels the timer on a manual toggle")
            print("PASS: \(locale) compact menu layout, native status-button and Settings actions; no startup write")
            print("PASS: \(locale) launch-at-login controls with a substituted system service; no OS login settings changed")
        }
        exerciseEvening(strings: .main, localized: false, require: require)
        exerciseEvening(strings: russian, localized: true, require: require)
        print("Input coverage: AppKit programmatic control actions; not mouse/AX interaction")
    }

    @MainActor private static func exerciseEvening(strings: Bundle, localized: Bool, require: (Bool, String) -> Void) {
        let backend = UIBackend()
        let display = GrayscaleController(backend: backend)
        let suite = "Monochrome.EveningMenuTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func state(_ enabled: Bool) -> NightShiftState {
            NightShiftState(enabled: enabled, mode: 0, schedule: [0,0,0,0], strength: 0.5, canActivate: true)
        }
        var warmth = state(false)
        var warmAvailable = true
        let evening = EveningController(defaults: defaults, grayscale: { try display.state() == .grayscale }, writeGray: { on, old in
            guard try display.setGrayscale(on, ifEnabled: old) else { throw NightShiftError.unconfirmed }
        }, warmth: {
            guard warmAvailable else { throw NightShiftError.unavailable }
            return warmth
        }, writeWarmth: { on, old in
            guard warmth == old else { throw NightShiftError.unconfirmed }; warmth = state(on)
        })
        let ui = StatusBarController(controller: display, strings: strings, evening: evening)
        defer { NSStatusBar.system.removeStatusItem(ui.statusItem) }
        ui.menu.delegate?.menuNeedsUpdate?(ui.menu)
        func click(_ title: String) {
            guard let i = ui.menu.items.firstIndex(where: { $0.title == title && $0.isEnabled }) else { require(false, "missing \(title)"); return }
            ui.menu.performActionForItem(at: i)
        }
        let warmTitle = localized ? "Тёплый экран" : "Warm Display"
        let eveningTitle = localized ? "Вечерний режим" : "Evening Mode"
        let endTitle = localized ? "Завершить вечерний режим" : "End Evening Mode"
        let settingsTitle = localized ? "Настройки" : "Settings"
        let scheduleTitle = localized ? "Расписание вечернего режима…" : "Evening Schedule…"
        require(backend.writes == 0 && !warmth.enabled, "evening is opt-in")
        click(warmTitle)
        require(warmth.enabled && backend.writes == 0, "menu Night Shift ignores grayscale")
        click(warmTitle)
        click(eveningTitle)
        require(warmth.enabled && backend.value == .grayscale, "evening action applies both filters")
        ui.statusItem.button?.performClick(nil)
        require(warmth.enabled && backend.value == .color, "left click only changes grayscale")
        click(endTitle)
        require(!warmth.enabled && backend.value == .color, "ending evening leaves manual grayscale state intact")
        let settings = ui.menu.items.first { $0.title == settingsTitle }?.submenu
        require(settings?.items.contains { $0.title == scheduleTitle && $0.isEnabled } == true, "settings contain an editable schedule")
        warmAvailable = false
        ui.menu.delegate?.menuNeedsUpdate?(ui.menu)
        require(ui.menu.items.first(where: { $0.title == eveningTitle })?.isEnabled == false, "unavailable Night Shift disables the combined action")
        ui.statusItem.button?.performClick(nil)
        require(backend.value == .grayscale && !warmth.enabled, "old shortcut path survives unsupported Night Shift")
        print("PASS: \(localized ? "ru" : "en") evening actions, isolated grayscale, unavailable fallback, and schedule menu")
    }
}
