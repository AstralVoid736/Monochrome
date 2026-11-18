import Carbon
import Foundation

@MainActor
final class NativeHotKeyRegistrar {
    static let signature: OSType = 0x4D4F4E4F // MONO
    private var handler: EventHandlerRef?
    var onRelease: ((UInt32) -> Bool)?

    deinit { if let handler { RemoveEventHandler(handler) } }

    func register(_ choice: HotKeyChoice, id: UInt32) throws -> () -> Void {
        let key: Int
        switch choice {
        case .one: key = kVK_ANSI_1
        case .two: key = kVK_ANSI_2
        case .three: key = kVK_ANSI_3
        case .off: throw HotKeyError.unavailable
        }
        try installHandler()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(key), UInt32(controlKey | cmdKey),
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &reference)
        if status == OSStatus(eventHotKeyExistsErr) { throw HotKeyError.occupied }
        guard status == noErr, let reference else { throw HotKeyError.unavailable }
        return {
            let status = UnregisterEventHotKey(reference)
            if status != noErr { NSLog("Monochrome could not unregister a shortcut (OSStatus %d)", status) }
        }
    }

    private func installHandler() throws {
        guard handler == nil else { return }
        // A release, rather than a repeating key-down, toggles once per keystroke.
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard result == noErr, Thread.isMainThread else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers application-target keyboard events on the main thread.
            return MainActor.assumeIsolated {
                guard key.signature == NativeHotKeyRegistrar.signature else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<NativeHotKeyRegistrar>.fromOpaque(context).takeUnretainedValue()
                return owner.onRelease?(key.id) == true ? noErr : OSStatus(eventNotHandledErr)
            }
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr, handler != nil else { throw HotKeyError.unavailable }
    }
}
