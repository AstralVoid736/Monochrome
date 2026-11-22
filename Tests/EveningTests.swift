import Foundation

@main struct EveningTests {
    @MainActor static func main() throws {
        func require(_ value: Bool, _ description: String) {
            if !value { print("FAIL: \(description)"); exit(1) }
        }
        let suite = "Monochrome.EveningTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        func time(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        let settings = EveningHours(start: 22 * 60, end: 7 * 60)!
        require(EveningHours.minute("00:00") == 0 && EveningHours.minute("23:59") == 1439, "24-hour endpoints")
        require(["7:00", "24:00", "12:60", "12:00x", "−1:00"].allSatisfy { EveningHours.minute($0) == nil }, "reject malformed times")
        require(EveningHours(start: 8, end: 8) == nil && EveningHours(start: -1, end: 1440) == nil, "invalid or equal times rejected")
        require(settings.boundaries(at: time(21, 21), calendar: cal)?.active == false, "before evening")
        require(settings.boundaries(at: time(21, 22), calendar: cal)?.active == true, "at start")
        require(settings.boundaries(at: time(22, 6), calendar: cal)?.next == time(22, 7), "across midnight")
        require(settings.boundaries(at: time(22, 7), calendar: cal)?.active == false, "at end")
        let daytime = EveningHours(start: 9 * 60, end: 17 * 60)!
        require(daytime.boundaries(at: time(22, 10), calendar: cal)?.active == true, "same-day window")
        require(daytime.boundaries(at: time(22, 17), calendar: cal)?.active == false, "same-day end")
        var dst = cal
        dst.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let spring = dst.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 1))!
        require(EveningHours(start: 150, end: 240)?.boundaries(at: spring, calendar: dst)?.active == true, "skipped clock hour uses next valid time")
        print("PASS: evening boundaries, midnight, same-day and DST gap")

        var gray = false
        var warm = NightShiftState(enabled: false, mode: 0, schedule: [0,0,0,0], strength: 0.5, canActivate: true)
        var writes = [String]()
        var denyGray = false
        var denyWarmOff = false
        func setWarm(_ on: Bool, config mode: Int32 = 0, strength: Float = 0.5) {
            warm = NightShiftState(enabled: on, mode: mode, schedule: [0,0,0,0], strength: strength, canActivate: true)
        }
        func make() -> EveningController {
            EveningController(defaults: defaults, grayscale: {
                gray
            }, writeGray: { on, before in
                guard gray == before, !denyGray else { throw NightShiftError.rejected }
                gray = on; writes.append("gray:\(on)")
            }, warmth: { warm }, writeWarmth: { on, before in
                guard warm == before, on || !denyWarmOff else { throw NightShiftError.rejected }
                setWarm(on, config: before.mode, strength: before.strength); writes.append("warm:\(on)")
            })
        }
        let c = make()
        _ = c.update(at: time(21, 22), calendar: cal)
        require(writes.isEmpty && c.hours == nil, "default off, cold start must not alter the screen")
        try c.toggleWarmth()
        require(warm.enabled && !gray, "manual warmth is independent")
        try c.toggleWarmth()
        c.configure(settings)
        require(make().hours == settings, "schedule persists without applying at initialization")
        _ = c.update(at: time(21, 22), calendar: cal)
        require(gray && warm.enabled && c.isEvening, "scheduled entry enables both")
        let gCount = writes.count
        _ = c.update(at: time(21, 23), calendar: cal)
        require(writes.count == gCount, "wake in same window doesn't repeat writes")
        c.releaseGrayControl()
        gray = false
        _ = c.update(at: time(22, 6), calendar: cal)
        require(!gray && warm.enabled, "manual gray override wins for this interval")
        _ = c.update(at: time(22, 8), calendar: cal)
        require(!gray && !warm.enabled, "wake past end releases only owned warm")
        gray = true
        _ = c.update(at: time(22, 22), calendar: cal)
        require(warm.enabled && c.isEvening, "preexisting gray is borrowed without writes")
        try c.toggleEvening()
        require(!warm.enabled && gray && !c.isEvening, "ending profile leaves preexisting gray on")
        _ = c.update(at: time(23, 6), calendar: cal)
        require(!warm.enabled, "manual pause lasts to the next boundary")
        _ = c.update(at: time(23, 22), calendar: cal)
        require(warm.enabled, "following window can start")
        setWarm(true, strength: 0.6)
        _ = c.update(at: time(24, 7), calendar: cal)
        require(warm.enabled && gray, "external warmth change is not overwritten by cleanup")
        setWarm(false, config: 1)
        gray = false
        _ = c.update(at: time(24, 22), calendar: cal)
        require(!warm.enabled && !gray && !c.isEvening && c.problem == .systemSchedule, "no automated countermand of a system Night Shift schedule")
        c.configure(nil)
        require(make().hours == nil, "schedule can be disabled persistently")
        setWarm(false)
        denyGray = true
        do { try c.toggleEvening(); require(false, "partial start should fail") } catch {}
        require(!warm.enabled && !gray && !c.isEvening, "never leave a partial evening activation behind")
        denyGray = false
        try c.toggleEvening()
        denyWarmOff = true
        do { try c.toggleEvening(); require(false, "failed cleanup should be reported") } catch {}
        require(warm.enabled && !gray && c.isEvening, "failed cleanup remains available to retry")
        denyWarmOff = false
        try c.toggleEvening()
        require(!warm.enabled && !c.isEvening, "cleanup retry succeeds")
        print("PASS: defaults, independent controls, ownership, manual override, next window, refused system schedule, rollback and retry")
    }
}
