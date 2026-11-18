import Foundation

@main
@MainActor
struct HotKeyTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { print("FAIL: \(message)"); exit(1) }
    }

    static func main() {
        let defaults = UserDefaults(suiteName: "Monochrome.HotKeyTests.\(UUID().uuidString)")!
        var registrations: [HotKeyChoice: UInt32] = [:]
        var changes: [String] = []
        var toggles = 0
        let hotKey = HotKeyController(defaults: defaults) { choice, id in
            if choice == .three { throw HotKeyError.occupied }
            registrations[choice] = id
            changes.append("register \(choice.rawValue)")
            return {
                registrations[choice] = nil
                changes.append("release \(choice.rawValue)")
            }
        }
        hotKey.onToggle = { toggles += 1 }
        hotKey.start()
        require(hotKey.active == .one && toggles == 0, "startup registers the default without toggling")
        let first = registrations[.one]!
        require(!hotKey.receiveRelease(0), "an unrelated ID cannot invoke the toggle")
        require(hotKey.receiveRelease(first) && toggles == 1, "the active release invokes the toggle once")
        hotKey.select(.three)
        require(hotKey.active == .one && hotKey.failure == .occupied && registrations[.one] == first, "conflict retains the previous registration")
        require(defaults.string(forKey: HotKeyController.preferenceKey) == nil, "failed choice is not saved")
        hotKey.select(.two)
        let second = registrations[.two]!
        require(hotKey.active == .two && hotKey.failure == nil && registrations[.one] == nil, "successful change updates the active choice")
        require(changes == ["register one", "register two", "release one"], "register replacement before removing the old shortcut")
        require(defaults.string(forKey: HotKeyController.preferenceKey) == "two", "successful choice is persisted")
        hotKey.select(.two)
        require(registrations[.two] == second && changes.count == 3, "reselecting an active choice is idempotent")
        require(!hotKey.receiveRelease(first) && toggles == 1, "queued release from an old registration is ignored")
        hotKey.select(.off)
        require(hotKey.active == .off && registrations.isEmpty && !hotKey.receiveRelease(second), "off unregisters and ignores stale releases")
        require(defaults.string(forKey: HotKeyController.preferenceKey) == "off", "off persists")
        let restored = HotKeyController(defaults: defaults) { _, _ in
            print("FAIL: saved Off must not register"); exit(1)
        }
        restored.start()
        require(restored.active == .off && restored.failure == nil, "Off survives startup")
        defaults.set("three", forKey: HotKeyController.preferenceKey)
        let blocked = HotKeyController(defaults: defaults) { _, _ in throw HotKeyError.occupied }
        blocked.start()
        require(blocked.active == .off && blocked.failure == .occupied, "startup conflict is visible without registering another shortcut")
        require(defaults.string(forKey: HotKeyController.preferenceKey) == "three", "startup conflict preserves the choice for next launch")
        print("PASS: shortcut lifecycle, conflict rollback, persistence and stale-event rejection")
    }
}
