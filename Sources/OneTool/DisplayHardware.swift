// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint; adapted for 1Tool
import AppKit
import IOKit.graphics

enum DisplayHardware {
    static func displayInfoDictionary(_ id: CGDirectDisplayID) -> NSDictionary? {
        guard let create = BrightnessBridge.createInfoDictionary else { return nil }
        return create(id)?.takeRetainedValue() as NSDictionary?
    }

    static func displayName(_ id: CGDirectDisplayID, info: NSDictionary?,
                                    screenNames: [CGDirectDisplayID: String]) -> String {
        if let name = screenNames[id] { return name }
        if let names = info?["DisplayProductName"] as? [String: String],
           let name = names["en_US"] ?? names.first?.value {
            return name
        }
        return "Display"
    }

    static func displayIdentity(_ id: CGDirectDisplayID,
                                        info: NSDictionary?) -> BrightnessSupport.DisplayIdentity {
        var identity = BrightnessSupport.DisplayIdentity()
        guard let info else { return identity }
        identity.vendorID = (info[kDisplayVendorID] as? NSNumber)?.int64Value
        identity.productID = (info[kDisplayProductID] as? NSNumber)?.int64Value
        identity.weekOfManufacture = (info[kDisplayWeekOfManufacture] as? NSNumber)?.int64Value
        identity.yearOfManufacture = (info[kDisplayYearOfManufacture] as? NSNumber)?.int64Value
        identity.horizontalImageSize = (info[kDisplayHorizontalImageSize] as? NSNumber)?.int64Value
        identity.verticalImageSize = (info[kDisplayVerticalImageSize] as? NSNumber)?.int64Value
        identity.ioDisplayLocation = info[kIODisplayLocationKey] as? String
        if let names = info["DisplayProductName"] as? [String: String] {
            identity.productName = names["en_US"] ?? names.first?.value
        }
        identity.serialNumber = (info[kDisplaySerialNumber] as? NSNumber)?.int64Value
        return identity
    }

    // MARK: - IORegistry walk

    struct ExternalService {
        var identity: BrightnessSupport.ServiceIdentity
        var service: CFTypeRef
    }

    /// External displays hang off the IORegistry as a framebuffer entry
    /// (identity: EDID UUID, product attributes) followed by its AV service
    /// proxy (the I2C endpoint, tagged with its location). Only proxies
    /// marked External accept DDC; the built-in panel's proxy is Embedded.
    static func externalServices() -> [ExternalService] {
        guard let createWithService = BrightnessBridge.createWithService else { return [] }
        var results: [ExternalService] = []
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iterator = io_iterator_t()
        guard IORegistryEntryCreateIterator(root, kIOServicePlane,
                                            IOOptionBits(kIORegistryIterateRecursively),
                                            &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var pending = BrightnessSupport.ServiceIdentity()
        var ordinal = 0
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else { break }
            defer { IOObjectRelease(entry) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &nameBuffer) == KERN_SUCCESS else { continue }
            let name = String(cString: nameBuffer)

            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                ordinal += 1
                pending = BrightnessSupport.ServiceIdentity()
                pending.ordinal = ordinal
                if let uuid = Self.property(entry, "EDID UUID") as? String {
                    pending.edidUUID = uuid
                }
                var path = [CChar](repeating: 0, count: 512)
                if IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS {
                    pending.ioDisplayLocation = String(cString: path)
                }
                if let attributes = Self.property(entry, "DisplayAttributes") as? NSDictionary,
                   let product = attributes["ProductAttributes"] as? NSDictionary {
                    pending.productName = product["ProductName"] as? String ?? ""
                    pending.serialNumber = (product["SerialNumber"] as? NSNumber)?.int64Value ?? 0
                }
            } else if name == "DCPAVServiceProxy" {
                guard let location = Self.property(entry, "Location") as? String,
                      location == "External",
                      let service = createWithService(kCFAllocatorDefault, entry)?.takeRetainedValue()
                else { continue }
                results.append(ExternalService(identity: pending, service: service))
            }
        }
        return results
    }

    static func property(_ entry: io_service_t, _ key: String) -> AnyObject? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively))?
            .takeRetainedValue()
    }
}
