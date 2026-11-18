import Foundation

enum HotKeyChoice: String, CaseIterable {
    case one, two, three, off

    var label: String {
        switch self {
        case .one: return "⌃⌘1"
        case .two: return "⌃⌘2"
        case .three: return "⌃⌘3"
        case .off: return "Off"
        }
    }
}

enum HotKeyError: Error, Equatable {
    case occupied
    case unavailable
}

@MainActor
final class HotKeyController {
    typealias Register = (HotKeyChoice, UInt32) throws -> () -> Void
    static let preferenceKey = "globalHotKey"

    private let defaults: UserDefaults
    private let register: Register
    private var cancel: (() -> Void)?
    private var activeID: UInt32?
    private var lastID: UInt32 = 0
    private(set) var active = HotKeyChoice.off
    private(set) var failure: HotKeyError?
    var onToggle: (() -> Void)?

    init(defaults: UserDefaults = .standard, register: @escaping Register) {
        self.defaults = defaults
        self.register = register
    }

    func start() {
        let choice = defaults.string(forKey: Self.preferenceKey).flatMap(HotKeyChoice.init(rawValue:)) ?? .one
        apply(choice, remember: false)
    }

    func select(_ choice: HotKeyChoice) { apply(choice, remember: true) }

    func stop() {
        active = .off
        activeID = nil
        cancel?()
        cancel = nil
    }

    @discardableResult
    func receiveRelease(_ id: UInt32) -> Bool {
        guard activeID == id else { return false }
        onToggle?()
        return true
    }

    private func apply(_ choice: HotKeyChoice, remember: Bool) {
        if choice == .off {
            stop()
        } else if choice != active {
            lastID &+= 1
            do {
                let replacement = try register(choice, lastID)
                let previous = cancel
                active = choice
                activeID = lastID
                cancel = replacement
                previous?()
            } catch {
                failure = (error as? HotKeyError) ?? .unavailable
                return
            }
        }
        failure = nil
        if remember { defaults.set(choice.rawValue, forKey: Self.preferenceKey) }
    }
}
