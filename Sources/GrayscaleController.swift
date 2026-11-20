import Foundation

enum FilterState: Equatable {
    case color
    case grayscale
    case otherFilter(Int32)
}

enum GrayscaleError: Error, LocalizedError {
    case unavailable(String)
    case conflictingFilter
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable(let detail): return "Системный способ переключения недоступен. \(detail)"
        case .conflictingFilter: return "В macOS включён другой цветовой фильтр. Monochrome не будет заменять его. Сначала отключи его в настройках универсального доступа."
        case .verificationFailed: return "macOS не подтвердила переключение. Текущее состояние не будет выдано за успешное изменение."
        }
    }
}

protocol GrayscaleBackend {
    func readState() throws -> FilterState
    func writeGrayscale(_ enabled: Bool) throws
}

final class GrayscaleController {
    private let backend: any GrayscaleBackend

    init(backend: any GrayscaleBackend) { self.backend = backend }
    func state() throws -> FilterState { try backend.readState() }

    @discardableResult
    func toggle() throws -> FilterState {
        let before = try backend.readState()
        if case .otherFilter = before { throw GrayscaleError.conflictingFilter }
        return try applyGrayscale(before == .color)
    }

    /// Leaves another filter intact, and changes nothing if the expected mode is no longer active.
    func setGrayscale(_ enabled: Bool, ifEnabled current: Bool) throws -> Bool {
        guard enabled != current, try state() == (current ? .grayscale : .color) else { return false }
        _ = try applyGrayscale(enabled)
        return true
    }

    private func applyGrayscale(_ enabled: Bool) throws -> FilterState {
        let expected: FilterState = enabled ? .grayscale : .color
        try backend.writeGrayscale(enabled)
        let observed = try backend.readState()
        guard observed == expected else { throw GrayscaleError.verificationFailed }
        return observed
    }
}
