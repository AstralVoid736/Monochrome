import Foundation
import Darwin

// Independent system read-back and exact cleanup for this explicitly requested smoke test.
final class FilterFixture {
    typealias GetBool = @convention(c) (Int32) -> Bool
    typealias GetInt = @convention(c) (Int32) -> Int32
    typealias SetBool = @convention(c) (Int32, Bool) -> Void
    typealias SetInt = @convention(c) (Int32, Int32) -> Void
    typealias CGGet = @convention(c) () -> Bool
    typealias CGSet = @convention(c) (Bool) -> Void
    typealias Sync = @convention(c) () -> Void
    typealias Wake = @convention(c) (Int32) -> Void
    let handles: [UnsafeMutableRawPointer]
    let enabled: GetBool
    let kind: GetInt
    let setEnabled: SetBool
    let setKind: SetInt
    let legacy: CGGet
    let setLegacy: CGSet
    let sync: Sync
    let wake: Wake
    struct Snapshot: Equatable { let enabled: Bool; let kind: Int32; let legacy: Bool }
    init() throws {
        let media = dlopen("/System/Library/Frameworks/MediaAccessibility.framework/MediaAccessibility", RTLD_LAZY)!
        let access = dlopen("/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess", RTLD_LAZY)!
        let cg = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)!
        handles = [media, access, cg]
        func load<T>(_ h: UnsafeMutableRawPointer, _ name: String, _ t: T.Type) -> T { unsafeBitCast(dlsym(h, name)!, to: t) }
        enabled = load(media, "MADisplayFilterPrefGetCategoryEnabled", GetBool.self)
        kind = load(media, "MADisplayFilterPrefGetType", GetInt.self)
        setEnabled = load(media, "MADisplayFilterPrefSetCategoryEnabled", SetBool.self)
        setKind = load(media, "MADisplayFilterPrefSetType", SetInt.self)
        legacy = load(cg, "CGDisplayUsesForceToGray", CGGet.self)
        setLegacy = load(cg, "CGDisplayForceToGray", CGSet.self)
        sync = load(access, "UAGrayscaleSynchronizeLegacyPref", Sync.self)
        wake = load(access, "_UniversalAccessDStart", Wake.self)
    }
    deinit { handles.reversed().forEach { dlclose($0) } }
    func snapshot() -> Snapshot { Snapshot(enabled: enabled(1), kind: kind(1), legacy: legacy()) }
    func restore(_ saved: Snapshot) {
        setKind(1, saved.kind)
        setEnabled(1, saved.enabled)
        sync()
        wake(8)
        setLegacy(saved.legacy)
    }
}
