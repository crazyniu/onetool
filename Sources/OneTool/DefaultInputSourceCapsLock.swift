// SPDX-License-Identifier: GPL-3.0-or-later
import IOKit
import IOKit.hidsystem

/// Use the same HID lock-state API as Super Key, without synthesizing keystrokes.
enum DefaultInputSourceCapsLock {
    enum Failure: Error {
        case unavailable
        case system(String, kern_return_t)
        var message: String {
            switch self {
            case .unavailable: return L("Input source applied. The Caps Lock hardware interface is unavailable.")
            case let .system(operation, status): return LF("Input source applied. Caps Lock operation %@ failed (system code %d).", operation, status)
            }
        }
    }
    static func clear() -> Bool { if case .success = clearResult() { return true }; return false }
    static func clearResult() -> Result<Void, Failure> {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return .failure(.unavailable) }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        let opened = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection)
        guard opened == KERN_SUCCESS else { return .failure(.system("IOServiceOpen", opened)) }
        defer { IOServiceClose(connection) }
        var isOn = false
        let read = IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &isOn)
        guard read == KERN_SUCCESS else { return .failure(.system("IOHIDGetModifierLockState", read)) }
        if !isOn { return .success(()) }
        let changed = IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), false)
        return changed == KERN_SUCCESS ? .success(()) : .failure(.system("IOHIDSetModifierLockState", changed))
    }
}
