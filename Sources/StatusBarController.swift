import AppKit
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

extension SMAppService: LoginItemService {
    func openSettings() { Self.openSystemSettingsLoginItems() }
}

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    let statusItem: NSStatusItem
    let menu = NSMenu()
    private let controller: GrayscaleController
    private let focusTimer: FocusTimerController
    private let strings: Bundle
    private let hotKey: HotKeyController?
    private let loginItem: (any LoginItemService)?
    private let loginAction = NSMenuItem(title: "", action: #selector(changeLoginItem), keyEquivalent: "")
    private let loginError = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var loginFailureStatus: SMAppService.Status?
    private let shortcutStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let shortcutMenu = NSMenu()
    private let timerAction = NSMenuItem(title: "", action: #selector(toggleTimer), keyEquivalent: "")
    private let timerStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var lastToggleError: String?
    private var lastTimerError: String?

    init(controller: GrayscaleController, strings: Bundle = .main, hotKey: HotKeyController? = nil,
         focusTimer: FocusTimerController? = nil, loginItem: (any LoginItemService)? = nil) {
        self.controller = controller
        self.focusTimer = focusTimer ?? FocusTimerController(display: controller)
        self.strings = strings
        self.hotKey = hotKey
        self.loginItem = loginItem
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let toggleItem = NSMenuItem(title: text("Enable Grayscale"), action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.tag = 1
        menu.addItem(toggleItem)
        timerAction.target = self
        menu.addItem(timerAction)
        timerStatus.isEnabled = false
        menu.addItem(timerStatus)
        self.focusTimer.onFinish = { [weak self] error in
            guard let self else { return }
            self.lastTimerError = error.map { _ in self.text("The timer ended, but color could not be restored.") }
            self.refresh()
        }
        menu.addItem(.separator())
        addSettingsMenu()
        let aboutItem = NSMenuItem(title: text("About Monochrome…"), action: #selector(about), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        let quitItem = NSMenuItem(title: text("Quit Monochrome"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.autoenablesItems = false
        menu.delegate = self
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusButtonPressed)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel(text("Monochrome — toggle grayscale"))
        }
        refresh()
    }

    private func addSettingsMenu() {
        guard hotKey != nil || loginItem != nil else { return }
        let title = text("Settings")
        let settings = NSMenu(title: title)
        settings.autoenablesItems = false
        settings.delegate = self
        if loginItem != nil {
            loginAction.title = text("Launch at Login")
            loginAction.target = self
            loginError.title = text("Could Not Change Launch at Login")
            loginError.isEnabled = false
            loginError.isHidden = true
            settings.addItem(loginAction)
            settings.addItem(loginError)
        }
        if hotKey != nil {
            let shortcutItem = NSMenuItem(title: text("Keyboard Shortcut"), action: nil, keyEquivalent: "")
            shortcutMenu.autoenablesItems = false
            shortcutStatus.isEnabled = false
            shortcutMenu.addItem(shortcutStatus)
            shortcutMenu.addItem(.separator())
            for (index, choice) in HotKeyChoice.allCases.enumerated() {
                let item = NSMenuItem(title: text(choice.label), action: #selector(selectShortcut(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                shortcutMenu.addItem(item)
            }
            shortcutItem.submenu = shortcutMenu
            settings.addItem(shortcutItem)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = settings
        menu.addItem(item)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === self.menu { refresh() }
        refreshLoginItem()
    }
    func stopTimer() { focusTimer.cancel() }

    @objc private func selectShortcut(_ sender: NSMenuItem) {
        guard HotKeyChoice.allCases.indices.contains(sender.tag) else { return }
        hotKey?.select(HotKeyChoice.allCases[sender.tag])
        refresh()
    }

    private func text(_ english: String) -> String {
        strings.localizedString(forKey: english, value: english, table: nil)
    }

    private func refresh() {
        guard let button = statusItem.button, let toggleItem = menu.item(withTag: 1) else { return }
        let symbol: String
        var canStartTimer = false
        do {
            let current = try controller.state()
            canStartTimer = current == .color
            if current != .grayscale && focusTimer.isActive { focusTimer.cancel() }
            switch current {
            case .grayscale:
                symbol = "circle.lefthalf.filled"
                toggleItem.title = text("Restore Color")
                toggleItem.state = .on
                button.toolTip = text("Monochrome: grayscale. Click to restore color. Right-click for menu.")
            case .color:
                symbol = "circle"
                toggleItem.title = text("Enable Grayscale")
                toggleItem.state = .off
                button.toolTip = text("Monochrome: color. Click to enable grayscale. Right-click for menu.")
            case .otherFilter:
                symbol = "exclamationmark.circle"
                toggleItem.title = text("Another color filter is active")
                toggleItem.state = .off
                button.toolTip = text("Monochrome: another system filter is active and will not be replaced. Right-click for menu.")
            }
            if case .otherFilter = current { toggleItem.isEnabled = false }
            else { toggleItem.isEnabled = true }
        } catch {
            symbol = "exclamationmark.circle"
            toggleItem.title = text("Color switching unavailable")
            toggleItem.state = .off
            toggleItem.isEnabled = false
            button.toolTip = "Monochrome: \(error.localizedDescription)"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Monochrome")
        button.image?.isTemplate = true
        timerAction.title = text(focusTimer.isActive ? "End Timer and Restore Color" : "Grayscale for 25 Minutes")
        timerAction.isEnabled = focusTimer.isActive || canStartTimer
        let timerMessage = lastTimerError ?? focusTimer.remainingMinutes.map { minutes in
            String(format: text("Time left (min): %lld"), minutes)
        }
        timerStatus.title = timerMessage ?? ""
        timerStatus.isHidden = timerMessage == nil
        if let hotKey {
            let status = String(format: text("Active: %@"), text(hotKey.active.label))
            switch hotKey.failure {
            case .occupied: shortcutStatus.title = String(format: text("Shortcut in use. %@"), status)
            case .unavailable: shortcutStatus.title = String(format: text("Could not register shortcut. %@"), status)
            case nil: shortcutStatus.title = status
            }
            for (choice, item) in zip(HotKeyChoice.allCases, shortcutMenu.items.dropFirst(2)) {
                item.state = choice == hotKey.active ? .on : .off
            }
            if hotKey.active != .off {
                button.toolTip = [button.toolTip, String(format: text("Shortcut: %@"), hotKey.active.label)].compactMap { $0 }.joined(separator: "\n")
            }
        }
        if let lastToggleError {
            button.toolTip = [button.toolTip, lastToggleError].compactMap { $0 }.joined(separator: "\n")
        }
        if let timerMessage {
            button.toolTip = [button.toolTip, timerMessage].compactMap { $0 }.joined(separator: "\n")
        }
    }

    private func refreshLoginItem() {
        guard let loginItem else { return }
        let status = loginItem.status
        if status != loginFailureStatus { loginFailureStatus = nil }
        loginError.isHidden = loginFailureStatus == nil || status == .requiresApproval
        loginAction.state = .off
        loginAction.isEnabled = true
        loginAction.title = text("Launch at Login")
        switch status {
        case .enabled:
            loginAction.state = .on
        case .notRegistered:
            break
        case .requiresApproval:
            loginAction.state = .mixed
            loginAction.title = text("Launch at Login — Review in System Settings…")
        case .notFound:
            loginAction.isEnabled = false
            loginAction.title = text("Launch at Login Unavailable")
        @unknown default:
            loginAction.isEnabled = false
            loginAction.title = text("Launch at Login Unavailable")
        }
    }

    @objc private func changeLoginItem() {
        guard let loginItem else { return }
        loginFailureStatus = nil
        defer { refreshLoginItem() }
        do {
            switch loginItem.status {
            case .enabled: try loginItem.unregister()
            case .notRegistered: try loginItem.register()
            case .requiresApproval: loginItem.openSettings()
            case .notFound: break
            @unknown default: break
            }
        } catch {
            loginFailureStatus = loginItem.status
        }
    }

    @objc private func statusButtonPressed() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            if let button = statusItem.button {
                menuNeedsUpdate(menu)
                NSMenu.popUpContextMenu(menu, with: event, for: button)
            }
        } else { toggle() }
    }

    @objc private func toggle() { switchDisplay(showAlert: true) }

    func toggleFromHotKey() { switchDisplay(showAlert: false) }

    @objc private func toggleTimer() {
        do {
            if focusTimer.isActive { try focusTimer.endEarly() }
            else { _ = try focusTimer.start() }
            lastTimerError = nil
        } catch {
            lastTimerError = text(focusTimer.isActive ? "Could not end the timer." : "Could not start the timer.")
        }
        refresh()
    }

    private func switchDisplay(showAlert: Bool) {
        do {
            try focusTimer.toggleManually()
            lastToggleError = nil
            lastTimerError = nil
            refresh()
        } catch {
            lastToggleError = error.localizedDescription
            refresh()
            guard showAlert else { return }
            let alert = NSAlert()
            alert.messageText = text("Could not switch the display")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: text("OK"))
            alert.runModal()
        }
    }

    @objc private func about() {
        let alert = NSAlert()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        alert.messageText = version.map { "Monochrome \($0)" } ?? "Monochrome"
        alert.informativeText = text("Left-click the menu bar icon to switch between color and grayscale. Right-click to open the menu. Quitting does not restore color.\n\nMonochrome uses undocumented macOS APIs and may not work on future versions.")
        alert.addButton(withTitle: text("Close"))
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
