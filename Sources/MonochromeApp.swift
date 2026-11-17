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
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
