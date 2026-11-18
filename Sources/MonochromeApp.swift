import AppKit

private struct UnavailableBackend: GrayscaleBackend {
    let reason: Error
    func readState() throws -> FilterState { throw reason }
    func writeGrayscale(_ enabled: Bool) throws { throw reason }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let backend: any GrayscaleBackend
        do { backend = try NativeGrayscaleBackend() }
        catch { backend = UnavailableBackend(reason: error) }
        statusBar = StatusBarController(controller: GrayscaleController(backend: backend))
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
