import AppKit
import ServiceManagement

private struct UnavailableBackend: GrayscaleBackend {
    let reason: Error
    func readState() throws -> FilterState { throw reason }
    func writeGrayscale(_ enabled: Bool) throws { throw reason }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var hotKey: HotKeyController?
    private var clockObservers: [(NotificationCenter, NSObjectProtocol)] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let backend: any GrayscaleBackend
        do { backend = try NativeGrayscaleBackend() }
        catch { backend = UnavailableBackend(reason: error) }
        let display = GrayscaleController(backend: backend)
        let night = try? NativeNightShift()
        let evening = EveningController(grayscale: {
            switch try display.state() {
            case .color: return false
            case .grayscale: return true
            case .otherFilter: throw GrayscaleError.conflictingFilter
            }
        }, writeGray: { enabled, current in
            guard try display.setGrayscale(enabled, ifEnabled: current) else { throw GrayscaleError.verificationFailed }
        }, warmth: {
            guard let night else { throw NightShiftError.unavailable }
            return try night.read()
        }, writeWarmth: { enabled, current in
            guard let night else { throw NightShiftError.unavailable }
            try night.set(enabled, from: current)
        })
        let registrar = NativeHotKeyRegistrar()
        let hotKey = HotKeyController(register: registrar.register)
        registrar.onRelease = { [weak hotKey] id in hotKey?.receiveRelease(id) ?? false }
        let statusBar = StatusBarController(controller: display, hotKey: hotKey,
                                            loginItem: SMAppService.mainApp, evening: evening)
        self.statusBar = statusBar
        self.hotKey = hotKey
        hotKey.onToggle = { [weak statusBar] in statusBar?.toggleFromHotKey() }
        hotKey.start()
        statusBar.updateEveningClock()
        let system = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        for (center, name) in [(workspace, NSWorkspace.didWakeNotification), (system, .NSSystemClockDidChange), (system, .NSSystemTimeZoneDidChange)] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak statusBar] _ in
                MainActor.assumeIsolated { statusBar?.updateEveningClock() }
            }
            clockObservers.append((center, token))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for (center, token) in clockObservers { center.removeObserver(token) }
        clockObservers.removeAll()
        statusBar?.stopTimer()
        statusBar?.stopEvening()
        hotKey?.stop()
    }
}

@main
struct MonochromeApp {
    @MainActor
    static func main() {
        do {
            guard let lock = try SingleInstanceLock.acquire() else { return }
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let delegate = AppDelegate()
            app.delegate = delegate
            withExtendedLifetime((lock, delegate)) { app.run() }
        } catch {
            NSLog("Monochrome could not acquire its startup lock: %@", error.localizedDescription)
            exit(EXIT_FAILURE)
        }
    }
}
