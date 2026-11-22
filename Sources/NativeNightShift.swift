import Darwin
import Foundation
import ObjectiveC

enum NightShiftError: Error { case unavailable, rejected, unconfirmed }

struct NightShiftState: Equatable {
    let enabled: Bool
    let mode: Int32
    let schedule: [Int32]
    let strength: Float
    let canActivate: Bool
}

/// Runtime-checked private API. Never changes the system schedule or warmth.
final class NativeNightShift {
    private typealias Make = @convention(c) (AnyClass, Selector) -> Unmanaged<AnyObject>?
    private typealias Support = @convention(c) (AnyClass, Selector) -> UInt8
    private typealias Status = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> UInt8
    private typealias Strength = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Float>) -> UInt8
    private typealias SetEnabled = @convention(c) (AnyObject, Selector, UInt8) -> UInt8
    private static let library = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY | RTLD_LOCAL)
    private let client: AnyObject
    private let status: Status
    private let strength: Strength
    private let setEnabled: SetEnabled
    private let statusSEL = NSSelectorFromString("getBlueLightStatus:")
    private let strengthSEL = NSSelectorFromString("getStrength:")
    private let setSEL = NSSelectorFromString("setEnabled:")

    init() throws {
        func checked(_ method: Method?, _ encodings: [String]) throws -> IMP {
            guard let method, let encoding = method_getTypeEncoding(method), encodings.contains(String(cString: encoding)) else {
                throw NightShiftError.unavailable
            }
            return method_getImplementation(method)
        }
        guard Self.library != nil, let cls = NSClassFromString("CBBlueLightClient") else { throw NightShiftError.unavailable }
        let support = NSSelectorFromString("supportsBlueLightReduction")
        let supports = try checked(class_getClassMethod(cls, support), ["B16@0:8", "c16@0:8"])
        guard unsafeBitCast(supports, to: Support.self)(cls, support) == 1 else { throw NightShiftError.unavailable }
        status = unsafeBitCast(try checked(class_getInstanceMethod(cls, statusSEL), ["B24@0:8^{?=BBBi{?={?=ii}{?=ii}}QB}16", "c24@0:8^{?=ccci{?={?=ii}{?=ii}}Qc}16"]), to: Status.self)
        strength = unsafeBitCast(try checked(class_getInstanceMethod(cls, strengthSEL), ["B24@0:8^f16", "c24@0:8^f16"]), to: Strength.self)
        setEnabled = unsafeBitCast(try checked(class_getInstanceMethod(cls, setSEL), ["B20@0:8B16", "c20@0:8c16"]), to: SetEnabled.self)
        let make = NSSelectorFromString("new")
        let makeIMP = try checked(class_getClassMethod(cls, make), ["@16@0:8"])
        guard let client = unsafeBitCast(makeIMP, to: Make.self)(cls, make)?.takeRetainedValue() else { throw NightShiftError.unavailable }
        self.client = client
    }

    func read() throws -> NightShiftState {
        // The accepted ObjC encodings have a 40-byte C layout on 64-bit macOS.
        var words = [UInt64](repeating: 0, count: 5)
        var warmth: Float = -1
        let state = try words.withUnsafeMutableBytes { raw -> NightShiftState in
            guard let address = raw.baseAddress, status(client, statusSEL, address) == 1,
                  strength(client, strengthSEL, &warmth) == 1, (0...1).contains(warmth),
                  raw[1] <= 1, raw[32] == 1 else { throw NightShiftError.unavailable }
            let mode = raw.load(fromByteOffset: 4, as: Int32.self)
            guard (0...2).contains(mode) else { throw NightShiftError.unavailable }
            return NightShiftState(enabled: raw[1] == 1, mode: mode,
                                   schedule: [8, 12, 16, 20].map { raw.load(fromByteOffset: $0, as: Int32.self) },
                                   strength: warmth, canActivate: raw.load(fromByteOffset: 24, as: UInt64.self) == 0)
        }
        return state
    }

    func set(_ enabled: Bool, from current: NightShiftState) throws {
        guard try read() == current else { throw NightShiftError.unconfirmed }
        guard current.enabled != enabled else { return }
        guard !enabled || current.canActivate else { throw NightShiftError.unavailable }
        guard setEnabled(client, setSEL, enabled ? 1 : 0) == 1 else { throw NightShiftError.rejected }
        let observed = try read()
        guard observed.enabled == enabled, observed.mode == current.mode, observed.schedule == current.schedule,
              observed.strength == current.strength else { throw NightShiftError.unconfirmed }
    }
}
