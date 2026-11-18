import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    let statusItem: NSStatusItem
    let menu = NSMenu()
    private let controller: GrayscaleController
    private let strings: Bundle
    private let hotKey: HotKeyController?
    private let shortcutStatus = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let shortcutMenu = NSMenu()
    private var lastToggleError: String?

    init(controller: GrayscaleController, strings: Bundle = .main, hotKey: HotKeyController? = nil) {
        self.controller = controller
        self.strings = strings
        self.hotKey = hotKey
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let title = NSMenuItem(title: "Monochrome", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let toggleItem = NSMenuItem(title: text("Enable Grayscale"), action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.tag = 1
        menu.addItem(toggleItem)
        let hint = NSMenuItem(title: text("Left-click to switch · right-click for menu"), action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
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
            menu.addItem(shortcutItem)
        }
        menu.addItem(.separator())
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

    func menuWillOpen(_ menu: NSMenu) { refresh() }

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
        do {
            let current = try controller.state()
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
    }

    @objc private func statusButtonPressed() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            refresh()
            if let button = statusItem.button { NSMenu.popUpContextMenu(menu, with: event, for: button) }
        } else { toggle() }
    }

    @objc private func toggle() { switchDisplay(showAlert: true) }

    func toggleFromHotKey() { switchDisplay(showAlert: false) }

    private func switchDisplay(showAlert: Bool) {
        do {
            try controller.toggle()
            lastToggleError = nil
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
