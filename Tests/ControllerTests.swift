import Foundation

final class TestBackend: GrayscaleBackend {
    var state: FilterState = .color
    var writes: [Bool] = []
    var ignoreWrites = false
    var readFailure = false
    var writeFailure = false
    func readState() throws -> FilterState {
        if readFailure { throw GrayscaleError.unavailable("test read") }
        return state
    }
    func writeGrayscale(_ enabled: Bool) throws {
        if writeFailure { throw GrayscaleError.unavailable("test write") }
        writes.append(enabled)
        if !ignoreWrites { state = enabled ? .grayscale : .color }
    }
}

@main
struct ControllerTests {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { print("FAIL: \(message)"); exit(1) }
    }
    static func main() throws {
        let backend = TestBackend()
        let controller = GrayscaleController(backend: backend)
        let result = try controller.toggle()
        require(result == .grayscale, "color → grayscale must change and return the observed state")
        require(backend.writes == [true], "one toggle must send exactly one write")
        print("PASS: color → grayscale")
        backend.state = .color
        backend.ignoreWrites = true
        var rejected = false
        do { _ = try controller.toggle() }
        catch GrayscaleError.verificationFailed { rejected = true }
        require(rejected, "a write without observed change must be rejected")
        print("PASS: unconfirmed change rejected")
        backend.ignoreWrites = false
        backend.state = .otherFilter(2)
        let beforeWrites = backend.writes
        var conflict = false
        do { _ = try controller.toggle() }
        catch GrayscaleError.conflictingFilter { conflict = true }
        require(conflict && backend.writes == beforeWrites, "an active non-grayscale filter must not be overwritten")
        print("PASS: other accessibility filter preserved")
        backend.state = .grayscale
        let off = try controller.toggle()
        require(off == .color && backend.writes.last == false, "grayscale → color")
        print("PASS: grayscale → color")
        let readCount = backend.writes.count
        let readOnly = try controller.state()
        require(readOnly == .color && backend.writes.count == readCount, "reading state sends no writes")
        print("PASS: read-only state")
        backend.state = .grayscale // A change made outside the controller.
        let external = try controller.toggle()
        require(external == .color, "toggle reads current system state, not a stale local flag")
        print("PASS: external state respected")
        backend.readFailure = true
        var readRejected = false
        let writesBeforeFailure = backend.writes.count
        do { _ = try controller.toggle() } catch { readRejected = true }
        require(readRejected && backend.writes.count == writesBeforeFailure, "read failure must send no write")
        print("PASS: read failure propagated")
        backend.readFailure = false
        backend.writeFailure = true
        var writeRejected = false
        do { _ = try controller.toggle() } catch { writeRejected = true }
        require(writeRejected && backend.state == .color, "write failure must not report success")
        print("PASS: write failure propagated")
    }
}
