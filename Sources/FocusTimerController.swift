import Foundation

@MainActor
final class FocusTimerController {
    typealias Schedule = (Duration, @escaping @MainActor () -> Void) -> () -> Void

    private let display: GrayscaleController
    private let duration: Duration
    private let schedule: Schedule
    private var sessionID: UUID?
    private var cancelScheduled: (() -> Void)?
    private var deadline: ContinuousClock.Instant?
    var onFinish: ((Error?) -> Void)?
    var isActive: Bool { sessionID != nil }

    var remainingMinutes: Int64? {
        guard let deadline else { return nil }
        let remaining = max(.zero, ContinuousClock().now.duration(to: deadline)).components
        return remaining.seconds / 60 + (remaining.seconds % 60 > 0 || remaining.attoseconds > 0 ? 1 : 0)
    }

    init(display: GrayscaleController, duration: Duration = .seconds(1500), schedule: Schedule? = nil) {
        self.display = display
        self.duration = duration
        self.schedule = schedule ?? { duration, action in
            let task = Task { @MainActor in
                do { try await Task.sleep(for: duration, clock: .continuous) }
                catch { return }
                if !Task.isCancelled { action() }
            }
            return { task.cancel() }
        }
    }

    @discardableResult
    func start() throws -> Bool {
        guard !isActive, duration > .zero, try display.setGrayscale(true, ifEnabled: false) else { return false }
        let id = UUID()
        sessionID = id
        deadline = ContinuousClock().now + duration
        let cancel = schedule(duration) { [weak self] in self?.expire(id) }
        if sessionID == id { cancelScheduled = cancel } else { cancel() }
        return true
    }

    func toggleManually() throws {
        try display.toggle()
        cancel()
    }

    func endEarly() throws {
        guard isActive else { return }
        _ = try display.setGrayscale(false, ifEnabled: true)
        cancel()
    }

    func cancel() {
        sessionID = nil
        deadline = nil
        cancelScheduled?()
        cancelScheduled = nil
    }

    private func expire(_ id: UUID) {
        guard sessionID == id else { return }
        cancel()
        do {
            _ = try display.setGrayscale(false, ifEnabled: true)
            onFinish?(nil)
        } catch {
            onFinish?(error)
        }
    }
}
