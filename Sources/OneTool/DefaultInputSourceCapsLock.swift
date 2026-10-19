// SPDX-License-Identifier: GPL-3.0-or-later
import IOKit
import IOKit.hidsystem

/// Use the same HID lock-state API as Super Key, without synthesizing keystrokes.
enum DefaultInputSourceCapsLock {
    static func clear() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS
        else { return false }
        defer { IOServiceClose(connection) }
        var isOn = false
        guard IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &isOn) == KERN_SUCCESS
        else { return false }
        return !isOn || IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), false) == KERN_SUCCESS
    }
}
