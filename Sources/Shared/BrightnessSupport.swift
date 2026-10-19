// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint; adapted for 1Tool
import Foundation

enum BrightnessSupport {
    /// VCP code for luminance in the DDC/CI standard.
    static let luminanceCode: UInt8 = 0x10
    /// 7-bit I2C address DDC displays listen on.
    static let chipAddress: UInt32 = 0x37
    /// Sub-address DDC hosts write through.
    static let dataAddress: UInt32 = 0x51

    // Field-proven pacing: displays lose I2C transactions that arrive back to
    // back, so every write waits first, reads settle longer, and failures
    // retry after a pause instead of hammering the bus.
    static let writePauseMicroseconds: UInt32 = 10_000
    static let readPauseMicroseconds: UInt32 = 50_000
    static let retryPauseMicroseconds: UInt32 = 20_000
    static let writeCycles = 2
    static let retryAttempts = 4
    static let replyLength = 11

    /// Discovery keeps the normal number of reply chances. Every attempt but
    /// the last sends one request before its read, so the read and retry
    /// pauses keep those requests more than 50ms apart instead of pairing
    /// them 10ms apart.
    static func ddcProbeAttempts() -> Int {
        retryAttempts + 1
    }

    /// Some monitors answer NULL until a second request arrives a few
    /// milliseconds behind the first, which is why field implementations pair
    /// theirs. The last discovery attempt pairs them too, before a channel
    /// that never answered is written off and cached as write-only.
    static func ddcProbeWriteCycles(classifyingChannel: Bool,
                                    isFinalAttempt: Bool = false) -> Int {
        classifyingChannel && !isFinalAttempt ? 1 : writeCycles
    }

    static let defaultKeyboardLightLevel: Float = 0.5
    static let keyboardLightStep: Float = 1.0 / 16.0

    static func keyboardLightOnLevel(lastNonzero: Float?) -> Float {
        guard let lastNonzero, lastNonzero > 0 else { return defaultKeyboardLightLevel }
        return min(lastNonzero, 1)
    }

    /// A slider hands over whatever the drag produced. Nothing but a finite
    /// value inside the supported range reaches the private setter.
    static func sliderKeyboardLightLevel(_ level: Float) -> Float? {
        guard level.isFinite else { return nil }
        return min(max(level, 0), 1)
    }

    static func steppedKeyboardLightLevel(current: Float, direction: Int) -> Float {
        guard current.isFinite else { return 0 }
        let step = direction < 0 ? -keyboardLightStep : keyboardLightStep
        return min(max(current + step, 0), 1)
    }

    /// The DDC/CI standard also spaces whole commands apart: a host waits at
    /// least 50ms after one command before starting the next. The pauses
    /// above pace the steps inside a command; without this one, a slider
    /// drag or a held brightness key chains commands at the write pause,
    /// five times faster than monitors are promised, and some react to the
    /// stream by dropping their signal until they are power cycled
    /// (issue #301).
    static let commandIntervalMicroseconds: UInt64 = 50_000

    /// How long the next command must still wait, given when the previous
    /// one to the same display finished. A first command, or a clock that
    /// moved backwards, waits nothing.
    static func ddcCommandDelay(nowMicroseconds: UInt64,
                                lastCommandEndMicroseconds: UInt64?) -> UInt32 {
        guard let last = lastCommandEndMicroseconds, last <= nowMicroseconds else { return 0 }
        let elapsed = nowMicroseconds - last
        guard elapsed < commandIntervalMicroseconds else { return 0 }
        return UInt32(commandIntervalMicroseconds - elapsed)
    }

    /// Wraps a DDC payload: length-tagged header, payload, XOR checksum. The
    /// checksum seed covers the destination address, and the sub-address only
    /// participates for multi-byte payloads (single-byte requests omit it).
    static func packet(payload: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [UInt8(0x80 | (payload.count + 1)), UInt8(payload.count)]
        bytes.append(contentsOf: payload)
        let seed = UInt8(chipAddress << 1) ^ (payload.count == 1 ? 0 : UInt8(dataAddress))
        bytes.append(bytes.reduce(seed) { $0 ^ $1 })
        return bytes
    }

    /// Set VCP Feature packet (opcode 0x03 carried in the length header).
    static func writePacket(code: UInt8, value: UInt16) -> [UInt8] {
        packet(payload: [code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// Get VCP Feature request packet.
    static func readRequestPacket(code: UInt8) -> [UInt8] {
        packet(payload: [code])
    }

    /// Parses a Get VCP Feature reply: checksum first (seeded with the host
    /// address the display answers to), then the big-endian maximum and
    /// current values. Anything malformed reads as no reply, and so does a
    /// reply for another control: a monitor read too early hands back the
    /// answer to the previous request.
    static func parseReply(_ reply: [UInt8], code: UInt8) -> (current: UInt16, maximum: UInt16)? {
        guard reply.count >= replyLength else { return nil }
        let checksum = reply[0..<(reply.count - 1)].reduce(UInt8(0x50)) { $0 ^ $1 }
        guard checksum == reply[reply.count - 1], reply[0] == 0x6e, reply[1] == 0x88, reply[2] == 0x02, reply[3] == 0, reply[4] == code else { return nil }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return (current, maximum)
    }

    // MARK: - Display to service matching

    /// What CoreGraphics knows about a display, for scoring against an
    /// IORegistry service candidate.
    struct DisplayIdentity {
        var vendorID: Int64?
        var productID: Int64?
        var weekOfManufacture: Int64?
        var yearOfManufacture: Int64?
        var horizontalImageSize: Int64?
        var verticalImageSize: Int64?
        var ioDisplayLocation: String?
        var productName: String?
        var serialNumber: Int64?
    }

    /// What the IORegistry walk collected for one external service.
    struct ServiceIdentity {
        var edidUUID = ""
        var ioDisplayLocation = ""
        var productName = ""
        var serialNumber: Int64 = 0
        var ordinal = 0
    }

    /// The EDID UUID embeds identity fields at fixed positions; each one that
    /// matches the display scores a point, and the IORegistry path match is
    /// decisive on its own. Zero means the pair is unrelated.
    static func matchScore(service: ServiceIdentity, display: DisplayIdentity) -> Int {
        var score = 0
        func uuidChunk(at location: Int) -> String {
            String(service.edidUUID.prefix(location + 4).suffix(4))
        }
        if let vendor = display.vendorID, vendor > 0 {
            let key = String(format: "%04X", UInt16(clamping: vendor))
            if key != "0000", key == uuidChunk(at: 0) { score += 1 }
        }
        if let product = display.productID, product > 0 {
            let value = UInt16(clamping: product)
            let key = String(format: "%02X%02X", UInt8(value & 0xFF), UInt8(value >> 8))
            if key != "0000", key == uuidChunk(at: 4) { score += 1 }
        }
        if let week = display.weekOfManufacture, let year = display.yearOfManufacture, year >= 1990 {
            let key = String(format: "%02X%02X",
                             UInt8(clamping: week),
                             UInt8(clamping: year - 1990))
            if key != "0000", key == uuidChunk(at: 19) { score += 1 }
        }
        if let horizontal = display.horizontalImageSize, let vertical = display.verticalImageSize {
            let key = String(format: "%02X%02X",
                             UInt8(clamping: horizontal / 10),
                             UInt8(clamping: vertical / 10))
            if key != "0000", key == uuidChunk(at: 30) { score += 1 }
        }
        if !service.ioDisplayLocation.isEmpty, service.ioDisplayLocation == display.ioDisplayLocation {
            score += 10
        }
        if !service.productName.isEmpty,
           service.productName.lowercased() == display.productName?.lowercased() {
            score += 1
        }
        if service.serialNumber != 0, service.serialNumber == display.serialNumber {
            score += 1
        }
        return score
    }

    /// Greedy assignment, best scores first: each display and each service is
    /// used at most once, and zero-score pairs never match. Returns display
    /// index to service ordinal.
    static func assignServices(scores: [(displayIndex: Int, serviceOrdinal: Int, score: Int)])
        -> [Int: Int] {
        var assignment: [Int: Int] = [:]
        var takenServices = Set<Int>()
        for entry in scores.sorted(by: { $0.score > $1.score }) where entry.score > 0 {
            guard assignment[entry.displayIndex] == nil,
                  !takenServices.contains(entry.serviceOrdinal) else { continue }
            assignment[entry.displayIndex] = entry.serviceOrdinal
            takenServices.insert(entry.serviceOrdinal)
        }
        return assignment
    }
}
