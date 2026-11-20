import Foundation

final class TimerBackend: GrayscaleBackend {
    var current: FilterState = .color
    var writes: [Bool] = []
    var ignoreWrites = false
    func readState() throws -> FilterState { current }
    func writeGrayscale(_ enabled: Bool) throws {
        writes.append(enabled)
        if !ignoreWrites { current = enabled ? .grayscale : .color }
    }
}

@main
@MainActor
struct FocusTimerTests {
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        if try !condition() { print("FAIL: \(message)"); exit(1) }
    }

    static func main() async throws {
        let backend = TimerBackend()
        let controller = GrayscaleController(backend: backend)
        var scheduled: [Duration] = []
        var actions: [@MainActor () -> Void] = []
        var cancelCount = 0
        var completionErrors: [Bool] = []
        let timer = FocusTimerController(display: controller) { duration, action in
            scheduled.append(duration)
            actions.append(action)
            return { cancelCount += 1 }
        }
        timer.onFinish = { completionErrors.append($0 != nil) }
        try check(timer.start() && timer.isActive && backend.writes == [true], "confirmed color → grayscale starts one timer")
        try check(!timer.start() && scheduled == [.seconds(1500)], "default is 25 minutes, duplicate request does not stack")
        actions[0]()
        actions[0]()
        check(!timer.isActive && backend.writes == [true, false] && completionErrors == [false], "expiry restores color exactly once")
        try check(timer.start(), "a new session can start after expiry")
        try timer.toggleManually()
        try check(timer.start(), "a new session can start after a manual toggle")
        let written = backend.writes
        actions[1]()
        check(timer.isActive && backend.writes == written, "stale callback cannot end a newer session")
        backend.current = .otherFilter(2)
        actions[2]()
        check(!timer.isActive && backend.current == .otherFilter(2) && backend.writes == written, "expiry cannot replace an external filter")
        try check(!timer.start(), "timer cannot claim another filter")
        backend.current = .grayscale
        try check(!timer.start(), "timer cannot claim pre-existing grayscale")
        backend.current = .color
        backend.ignoreWrites = true
        do {
            _ = try timer.start()
            check(false, "unconfirmed switch must throw")
        } catch GrayscaleError.verificationFailed {}
        check(!timer.isActive && scheduled.count == 3, "failed start never schedules a callback")
        backend.ignoreWrites = false
        try check(timer.start(), "can start after failed write is resolved")
        backend.ignoreWrites = true
        do {
            try timer.toggleManually()
            check(false, "unconfirmed manual toggle must throw")
        } catch GrayscaleError.verificationFailed {}
        check(timer.isActive, "failed manual toggle does not cancel the timer")
        actions[3]()
        check(!timer.isActive && completionErrors.last == true, "failed automatic restoration is reported")
        backend.ignoreWrites = false
        backend.current = .color
        try check(timer.start(), "can start the early-finish check")
        try timer.endEarly()
        check(!timer.isActive && backend.current == .color && cancelCount == 5, "early finish restores color and clears the callback")
        try check(timer.start(), "can start the exit cancellation check")
        timer.cancel()
        actions[5]()
        check(!timer.isActive && backend.current == .grayscale, "cancelling on exit does not write the display")
        print("PASS: 25-minute scheduling, expiry, manual cancel, stale events, early finish, alternate filter and failed writes")

        let liveBackend = TimerBackend()
        let live = FocusTimerController(display: GrayscaleController(backend: liveBackend), duration: .milliseconds(35))
        try check(live.start(), "real one-shot clock can start")
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while live.isActive && clock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        check(!live.isActive && liveBackend.writes == [true, false], "real one-shot clock restores the test filter")
        print("PASS: real one-shot scheduling with a short interval and an isolated filter")
    }
}
