// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint; adapted for 1Tool
import AppKit
import IOKit.graphics
import ObjectiveC.runtime

enum BrightnessBridge {
    typealias GetBrightnessFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightnessFn = @convention(c) (UInt32, Float) -> Int32
    typealias CreateInfoDictionaryFn = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
    typealias CreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias WriteI2CFn = @convention(c)
        (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    typealias ReadI2CFn = @convention(c)
        (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let displayServicesHandle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let coreDisplayHandle = dlopen(
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)

    static let getBrightness: GetBrightnessFn? =
        symbol(displayServicesHandle, "DisplayServicesGetBrightness")
    static let setBrightness: SetBrightnessFn? =
        symbol(displayServicesHandle, "DisplayServicesSetBrightness")
    /// What the system's own brightness keys call. It takes a change, not a
    /// level: the reported level moves by that much at once and the
    /// backlight eases after it.
    static let setBrightnessSmooth: SetBrightnessFn? =
        symbol(displayServicesHandle, "DisplayServicesSetBrightnessSmooth")
    static let createInfoDictionary: CreateInfoDictionaryFn? =
        symbol(coreDisplayHandle, "CoreDisplay_DisplayCreateInfoDictionary")
    static let createWithService: CreateWithServiceFn? =
        symbol(coreDisplayHandle, "IOAVServiceCreateWithService")
    static let writeI2C: WriteI2CFn? =
        symbol(coreDisplayHandle, "IOAVServiceWriteI2C")
    static let readI2C: ReadI2CFn? =
        symbol(coreDisplayHandle, "IOAVServiceReadI2C")

    static var ddcAvailable: Bool {
        createWithService != nil && writeI2C != nil && readI2C != nil
    }

    private static func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

/// Keyboard backlighting has no public setter. Resolve the system client and
/// its methods at runtime so unsupported hardware or a future removal simply
/// hides the control instead of affecting launch.
final class KeyboardLightBridge {
    private typealias CopyIDsFn = @convention(c) (NSObject, Selector) -> Unmanaged<AnyObject>
    private typealias IsBuiltInFn = @convention(c) (NSObject, Selector, UInt64) -> ObjCBool
    private typealias GetBrightnessFn = @convention(c) (NSObject, Selector, UInt64) -> Float
    private typealias SetBrightnessFn = @convention(c)
        (NSObject, Selector, Float, Int32, Bool, UInt64) -> ObjCBool
    private typealias SuspendIdleDimmingFn = @convention(c)
        (NSObject, Selector, Bool, UInt64) -> ObjCBool

    private let client: NSObject
    private let keyboardID: UInt64
    private let getBrightness: GetBrightnessFn
    private let setBrightnessValue: SetBrightnessFn
    private let suspendIdleDimming: SuspendIdleDimmingFn
    private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let setSelector = NSSelectorFromString(
        "setBrightness:fadeSpeed:commit:forKeyboard:")
    private let suspendSelector = NSSelectorFromString("suspendIdleDimming:forKeyboard:")

    private typealias GetBoolFn = @convention(c) (NSObject, Selector, UInt64) -> ObjCBool
    private func flag(_ name: String) -> Bool? {
        let selector = NSSelectorFromString(name)
        guard let function = Self.implementation(client, selector: selector, as: GetBoolFn.self) else { return nil }
        return function(client, selector, keyboardID).boolValue
    }
    var autoBrightness: Bool? { flag("isAutoBrightnessEnabledForKeyboard:") }
    var suppressed: Bool { flag("isBacklightSuppressedOnKeyboard:") ?? false }
    func setAutoBrightness(_ enabled: Bool) -> Bool {
        let selector = NSSelectorFromString("enableAutoBrightness:forKeyboard:")
        guard let function = Self.implementation(client, selector: selector, as: SuspendIdleDimmingFn.self) else { return false }
        return function(client, selector, enabled, keyboardID).boolValue
    }

    init?() {
        guard let framework = Bundle(
            path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"),
              framework.load(),
              let clientClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }

        let client = clientClass.init()
        let copySelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        let builtInSelector = NSSelectorFromString("isKeyboardBuiltIn:")
        guard let copyIDs: CopyIDsFn = Self.implementation(
            client, selector: copySelector, as: CopyIDsFn.self),
              let isBuiltIn: IsBuiltInFn = Self.implementation(
                client, selector: builtInSelector, as: IsBuiltInFn.self),
              let getBrightness: GetBrightnessFn = Self.implementation(
                client, selector: getSelector, as: GetBrightnessFn.self),
              let setBrightness: SetBrightnessFn = Self.implementation(
                client, selector: setSelector, as: SetBrightnessFn.self),
              let suspendIdleDimming: SuspendIdleDimmingFn = Self.implementation(
                client, selector: suspendSelector, as: SuspendIdleDimmingFn.self),
              let ids = copyIDs(client, copySelector).takeRetainedValue() as? [NSNumber],
              let keyboardID = ids.map(\.uint64Value).first(where: {
                  isBuiltIn(client, builtInSelector, $0).boolValue
              })
        else { return nil }

        self.client = client
        self.keyboardID = keyboardID
        self.getBrightness = getBrightness
        self.setBrightnessValue = setBrightness
        self.suspendIdleDimming = suspendIdleDimming
    }

    func brightness() -> Float {
        getBrightness(client, getSelector, keyboardID)
    }

    func setBrightness(_ value: Float) -> Bool {
        let wasSuspended = flag("isIdleDimmingSuspendedOnKeyboard:") ?? false
        _ = suspendIdleDimming(client, suspendSelector, true, keyboardID)
        defer { _ = suspendIdleDimming(client, suspendSelector, wasSuspended, keyboardID) }
        return setBrightnessValue(client, setSelector, min(max(value, 0), 1), 350,
                                  true, keyboardID).boolValue
    }

    private static func implementation<Function>(
        _ object: NSObject,
        selector: Selector,
        as type: Function.Type
    ) -> Function? {
        guard let cls = object_getClass(object),
              let method = class_getInstanceMethod(cls, selector) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: type)
    }
}
