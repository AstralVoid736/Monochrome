import Foundation

struct EveningHours: Equatable {
    let start: Int
    let end: Int
    static let suggested = EveningHours(start: 22 * 60, end: 7 * 60)!

    init?(start: Int, end: Int) {
        guard (0..<1440).contains(start), (0..<1440).contains(end), start != end else { return nil }
        self.start = start
        self.end = end
    }

    static func minute(_ text: String) -> Int? {
        let b = Array(text.utf8)
        guard b.count == 5, b[2] == 58, [b[0], b[1], b[3], b[4]].allSatisfy({ (48...57).contains($0) }) else { return nil }
        let h = Int(b[0] - 48) * 10 + Int(b[1] - 48)
        let m = Int(b[3] - 48) * 10 + Int(b[4] - 48)
        guard h < 24, m < 60 else { return nil }
        return h * 60 + m
    }

    static func label(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }

    func boundaries(at date: Date, calendar: Calendar) -> (since: Date, active: Bool, next: Date)? {
        let today = calendar.startOfDay(for: date)
        var events: [(date: Date, on: Bool)] = []
        for offset in -2...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for (minute, on) in [(start, true), (end, false)] {
                let components = DateComponents(hour: minute / 60, minute: minute % 60, second: 0)
                if let point = calendar.nextDate(after: day.addingTimeInterval(-1), matching: components,
                                                 matchingPolicy: .nextTime, repeatedTimePolicy: .first),
                   calendar.isDate(point, inSameDayAs: day) {
                    events.append((point, on))
                }
            }
        }
        events.sort { $0.date == $1.date ? $0.on && !$1.on : $0.date < $1.date }
        guard let last = events.last(where: { $0.date <= date }), let next = events.first(where: { $0.date > date }) else { return nil }
        return (last.date, last.on, next.date)
    }
}

@MainActor final class EveningController {
    enum Problem: Error { case unavailable, changeFailed, systemSchedule }
    private static let key = "evening-hours-v1"
    private let defaults: UserDefaults
    private let grayscale: () throws -> Bool
    private let writeGray: (Bool, Bool) throws -> Void
    private let readWarmth: () throws -> NightShiftState
    private let writeWarmth: (Bool, NightShiftState) throws -> Void
    private var ownedGray = false
    private var ownedWarm: NightShiftState?
    private var session = false
    private var boundary: Date?
    private(set) var problem: Problem?
    private(set) var hours: EveningHours?
    var isEvening: Bool { session || ownedGray || ownedWarm != nil }

    init(defaults: UserDefaults = .standard, grayscale: @escaping () throws -> Bool,
         writeGray: @escaping (Bool, Bool) throws -> Void, warmth: @escaping () throws -> NightShiftState,
         writeWarmth: @escaping (Bool, NightShiftState) throws -> Void) {
        self.defaults = defaults
        self.grayscale = grayscale
        self.writeGray = writeGray
        self.readWarmth = warmth
        self.writeWarmth = writeWarmth
        if let encoded = defaults.string(forKey: Self.key) {
            let values = encoded.split(separator: "-", omittingEmptySubsequences: false)
            if values.count == 2, let start = EveningHours.minute(String(values[0])), let end = EveningHours.minute(String(values[1])) {
                hours = EveningHours(start: start, end: end)
            }
        }
    }

    func configure(_ hours: EveningHours?) {
        if self.hours == hours { return }
        finish()
        self.hours = hours
        boundary = nil
        if let hours { defaults.set("\(EveningHours.label(hours.start))-\(EveningHours.label(hours.end))", forKey: Self.key) }
        else { defaults.removeObject(forKey: Self.key) }
    }

    @discardableResult func update(at now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Date? {
        guard let slot = hours?.boundaries(at: now, calendar: calendar) else { return nil }
        if boundary != slot.since {
            boundary = slot.since
            finish()
            if !isEvening, slot.active { performStart(automatic: true) }
        }
        return slot.next
    }

    func warmth() throws -> NightShiftState { try readWarmth() }
    func releaseGrayControl() { ownedGray = false }

    func toggleWarmth() throws {
        let current = try readWarmth()
        try writeWarmth(!current.enabled, current)
        ownedWarm = nil
        problem = nil
    }

    func toggleEvening() throws {
        if isEvening { finish() }
        else { performStart(automatic: false) }
        if let problem { throw problem }
    }

    func shutdown() { finish() }

    private func performStart(automatic: Bool) {
        do {
            let g = try grayscale()
            let w = try readWarmth()
            if automatic && w.mode != 0 { problem = .systemSchedule; return }
            if !w.enabled {
                guard w.canActivate else { problem = .unavailable; return }
                let expected = NightShiftState(enabled: true, mode: w.mode, schedule: w.schedule, strength: w.strength, canActivate: w.canActivate)
                try writeWarmth(true, w)
                ownedWarm = expected
            }
            if !g {
                try writeGray(true, false)
                ownedGray = true
            }
            session = true
            problem = nil
        } catch {
            finish()
            if problem == nil { problem = error as? Problem ?? .changeFailed }
        }
    }

    private func finish() {
        session = false
        problem = nil
        if ownedGray {
            do {
                if try grayscale() { try writeGray(false, true) }
                ownedGray = false
            } catch { problem = .changeFailed }
        }
        if let expected = ownedWarm {
            do {
                if try readWarmth() == expected { try writeWarmth(false, expected) }
                ownedWarm = nil
            } catch { problem = .changeFailed }
        }
    }
}
