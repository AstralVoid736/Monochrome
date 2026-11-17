import Foundation
import Darwin

// Undocumented system symbols; resolve at runtime so unsupported systems fail safely.
final class NativeGrayscaleBackend: GrayscaleBackend {
    private typealias GetEnabled = @convention(c) (Int32) -> Bool
    private typealias GetType = @convention(c) (Int32) -> Int32
    private typealias SetGray = @convention(c) (Bool) -> Void
    private typealias Synchronize = @convention(c) () -> Void
    private typealias Wake = @convention(c) (Int32) -> Void

    private let libraries: [UnsafeMutableRawPointer]
    private let categoryEnabled: GetEnabled
    private let filterType: GetType
    private let setGray: SetGray
    private let synchronize: Synchronize
    private let wake: Wake

    init() throws {
        var opened: [UnsafeMutableRawPointer] = []
        func open(_ path: String) throws -> UnsafeMutableRawPointer {
            guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
                throw GrayscaleError.unavailable("Не удалось открыть системный framework.")
            }
            opened.append(handle)
            return handle
        }
        func symbol<T>(_ library: UnsafeMutableRawPointer, _ name: String, as type: T.Type) throws -> T {
            guard let address = dlsym(library, name) else { throw GrayscaleError.unavailable("Отсутствует \(name).") }
            return unsafeBitCast(address, to: type)
        }
        do {
            let media = try open("/System/Library/Frameworks/MediaAccessibility.framework/MediaAccessibility")
            let access = try open("/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess")
            categoryEnabled = try symbol(media, "MADisplayFilterPrefGetCategoryEnabled", as: GetEnabled.self)
            filterType = try symbol(media, "MADisplayFilterPrefGetType", as: GetType.self)
            setGray = try symbol(access, "UAGrayscaleSetEnabled", as: SetGray.self)
            synchronize = try symbol(access, "UAGrayscaleSynchronizeLegacyPref", as: Synchronize.self)
            wake = try symbol(access, "_UniversalAccessDStart", as: Wake.self)
            libraries = opened
        } catch {
            for handle in opened.reversed() { dlclose(handle) }
            throw error
        }
    }

    deinit { for handle in libraries.reversed() { dlclose(handle) } }

    func readState() throws -> FilterState {
        guard categoryEnabled(1) else { return .color }
        let kind = filterType(1)
        return kind == 1 ? .grayscale : .otherFilter(kind)
    }

    func writeGrayscale(_ enabled: Bool) throws {
        if case .otherFilter = try readState() { throw GrayscaleError.conflictingFilter }
        setGray(enabled)
        synchronize()
        wake(8)
    }
}
