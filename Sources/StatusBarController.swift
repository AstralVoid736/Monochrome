import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    let statusItem: NSStatusItem
    let menu = NSMenu()
    private let controller: GrayscaleController

    init(controller: GrayscaleController) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        let title = NSMenuItem(title: "Monochrome", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let toggleItem = NSMenuItem(title: "Включить оттенки серого", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.tag = 1
        menu.addItem(toggleItem)
        let hint = NSMenuItem(title: "Левый клик — переключить · правый — меню", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "О Monochrome…", action: #selector(about), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        let quitItem = NSMenuItem(title: "Выйти из Monochrome", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.autoenablesItems = false
        menu.delegate = self
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusButtonPressed)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Monochrome — переключение оттенков серого")
        }
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        guard let button = statusItem.button, let toggleItem = menu.item(withTag: 1) else { return }
        let symbol: String
        do {
            let current = try controller.state()
            switch current {
            case .grayscale:
                symbol = "circle.lefthalf.filled"
                toggleItem.title = "Вернуть цвета"
                toggleItem.state = .on
                button.toolTip = "Monochrome: чёрно-белый экран. Клик — вернуть цвета. Правый клик — меню."
            case .color:
                symbol = "circle"
                toggleItem.title = "Включить оттенки серого"
                toggleItem.state = .off
                button.toolTip = "Monochrome: цветной экран. Клик — включить оттенки серого. Правый клик — меню."
            case .otherFilter:
                symbol = "exclamationmark.circle"
                toggleItem.title = "Другой цветовой фильтр уже включён"
                toggleItem.state = .off
                button.toolTip = "Monochrome: включён другой системный фильтр; он не будет заменён. Правый клик — меню."
            }
            if case .otherFilter = current { toggleItem.isEnabled = false }
            else { toggleItem.isEnabled = true }
        } catch {
            symbol = "exclamationmark.circle"
            toggleItem.title = "Переключение недоступно"
            toggleItem.state = .off
            toggleItem.isEnabled = false
            button.toolTip = "Monochrome: \(error.localizedDescription)"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Monochrome")
        button.image?.isTemplate = true
    }

    @objc private func statusButtonPressed() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            refresh()
            if let button = statusItem.button { NSMenu.popUpContextMenu(menu, with: event, for: button) }
        } else { toggle() }
    }

    @objc private func toggle() {
        do {
            try controller.toggle()
            refresh()
        } catch {
            refresh()
            let alert = NSAlert()
            alert.messageText = "Не удалось переключить экран"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Понятно")
            alert.runModal()
        }
    }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "Monochrome 0.1.0"
        alert.informativeText = "Оттенки серого одним кликом.\nЛевый клик по значку — переключить. Правый — меню.\n\nБез сети, таймеров и автозапуска. Выход из приложения не отключает системный фильтр.\n\nИспользуются недокументированные API macOS; совместимость с будущими версиями не гарантируется."
        alert.addButton(withTitle: "Закрыть")
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
