import Foundation

@main
struct NativeSmoke {
    static func main() throws {
        guard CommandLine.arguments.contains("--allow-display-change") else {
            print("Refusing to change the display: pass --allow-display-change explicitly.")
            exit(2)
        }
        let fixture = try FilterFixture()
        let initial = fixture.snapshot()
        print("Initial: enabled=\(initial.enabled) kind=\(initial.kind) legacy=\(initial.legacy)")
        guard !initial.enabled || initial.kind == 1 else {
            print("SKIP: another accessibility filter is active; no display writes sent.")
            exit(3)
        }
        var failed = false
        defer {
            fixture.restore(initial)
            Thread.sleep(forTimeInterval: 0.25)
            let restored = fixture.snapshot()
            print("Restored: enabled=\(restored.enabled) kind=\(restored.kind) legacy=\(restored.legacy)")
            guard restored == initial else { print("FAIL: initial filter configuration not restored"); exit(1) }
            print("PASS: exact initial filter configuration restored")
            if failed { exit(1) }
        }
        let backend = try NativeGrayscaleBackend()
        let controller = GrayscaleController(backend: backend)
        let expected: FilterState = initial.enabled ? .color : .grayscale
        do {
            let observed = try controller.toggle()
            Thread.sleep(forTimeInterval: 0.25)
            let independent = fixture.snapshot()
            print("Observed: controller=\(observed) mediaEnabled=\(independent.enabled) type=\(independent.kind) legacyCG=\(independent.legacy)")
            let modernEnabled = independent.enabled && independent.kind == 1
            guard observed == expected, modernEnabled == (expected == .grayscale) else {
                print("FAIL: modern system filter preferences did not confirm the requested state")
                failed = true; return
            }
            print("PASS: native toggle + independent modern filter read-back (not a physical-screen observation)")
            let second = try controller.toggle()
            guard second == (initial.enabled ? .grayscale : .color) else {
                print("FAIL: reverse toggle"); failed = true; return
            }
            print("PASS: reverse native toggle")
        } catch {
            print("FAIL: native toggle: \(error.localizedDescription)")
            failed = true
        }
    }
}
