// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

@main struct Checks {
    static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ title: String) {
            guard value() else { fatalError("FAIL: " + title) }
            count += 1; print("PASS: " + title)
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onetool-checks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appBundle = Bundle(url: root.appendingPathComponent("build/1Tool.app"))!
        let finderBundle = Bundle(url: appBundle.bundleURL.appendingPathComponent("Contents/PlugIns/OneToolFinder.appex"))!
        check(StatusIconSelection.sanitized("flame.fill").isEmpty && StatusIconSelection.sanitized("cloud.fill").isEmpty, "legacy generic symbols migrate to the original wrench")
        check(StatusIconSelection.sanitized(" hexagon.fill ") == "hexagon.fill" && Set(StatusIconSelection.gallery).count == 32, "32 curated choices fill four aligned rows of eight")
        check(BrandGlyph.customMark(named: "minus") == nil, "reject a mark that becomes too short at menu-bar size")
        let appArtwork = try Data(contentsOf: appBundle.url(forResource: "AppIcon", withExtension: "icns")!)
        let finderArtwork = try Data(contentsOf: finderBundle.url(forResource: "AppIcon", withExtension: "icns")!)
        check(finderArtwork == appArtwork, "host and Finder extension carry identical app artwork")
        check(finderBundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String == "AppIcon", "Finder extension declares the shared app icon")
        let savedIcon = UserDefaults.standard.object(forKey: "appearance.icon")
        defer {
            if let savedIcon { UserDefaults.standard.set(savedIcon, forKey: "appearance.icon") }
            else { UserDefaults.standard.removeObject(forKey: "appearance.icon") }
        }
        func pixels(_ image: NSImage) -> NSBitmapImageRep {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 44,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(x: 0, y: 0, width: 44, height: 44))
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        for style in StatusIconSelection.gallery {
            UserDefaults.standard.set(style, forKey: "appearance.icon")
            let idleIcon = BrandGlyph.image(active: false, bundle: appBundle)!
            let activeIcon = BrandGlyph.image(active: true, bundle: appBundle)!
            check((style.isEmpty ? idleIcon.representations.count == 2 : BrandGlyph.customMark(named: style) != nil) && activeIcon.size == idleIcon.size && activeIcon.size == BrandGlyph.pointSize && !activeIcon.isTemplate && idleIcon.isTemplate, "menu icon is legible on a stable canvas without a dot: " + style)
            let activePixels = pixels(activeIcon), idlePixels = pixels(idleIcon)
            var greenPixels = 0, wrongColorPixels = 0
            var sameSilhouette = true
            for y in 0..<44 {
                for x in 0..<44 {
                    let color = activePixels.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    let idleAlpha = idlePixels.colorAt(x: x, y: y)!.alphaComponent
                    sameSilhouette = sameSilhouette && abs(color.alphaComponent - idleAlpha) < 0.05
                    if color.alphaComponent > 0.5 {
                        if color.greenComponent > color.redComponent && color.greenComponent > color.blueComponent { greenPixels += 1 }
                        else { wrongColorPixels += 1 }
                    }
                }
            }
            check(sameSilhouette && greenPixels > 20 && wrongColorPixels == 0, "active icon is entirely green and preserves the idle silhouette: " + style)
        }
        check(SuperRightClickFiles.validName("你好 ' $().txt"), "valid Unicode file name")
        for bad in ["", ".", "..", "a/b", "a:b", "a\0b", String(repeating: "a", count: 256)] {
            check(!SuperRightClickFiles.validName(bad), "reject invalid file name")
        }
        let file = try SuperRightClickFiles.create(name: "one.txt", in: dir, content: Data("first".utf8))
        var refused = false
        do { _ = try SuperRightClickFiles.create(name: "one.txt", in: dir, content: Data("second".utf8)) } catch { refused = true }
        check(refused, "existing file is not overwritten")
        let data = try Data(contentsOf: file)
        check(data == Data("first".utf8), "existing file content preserved")
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("link.txt").path, withDestinationPath: file.path)
        refused = false
        do { _ = try SuperRightClickFiles.create(name: "link.txt", in: dir, content: Data()) } catch { refused = true }
        check(refused, "symlink target is not overwritten")
        check(SuperRightClickFiles.insertionDirectory(target: file.path, selection: [file.path])?.path == dir.path, "selected file resolves to parent")
        check(!SuperRightClickTemplates.validExtension("../sh"), "template extension cannot traverse")
        check(SuperRightClickTemplates.normalizedExtension(" .JSON ") == "json", "extension normalization")
        let template = SuperRightClickTemplatePreset.json.entry
        let templateData = try SuperRightClickTemplates.data(for: template, resourceDirectory: nil)
        check(templateData == Data("{}\n".utf8), "JSON template contents")
        check(AppLanguage.resolve("system", preferred: ["de-DE"]) == "de", "language follows regional system preference")
        check(AppLanguage.resolve("system", preferred: ["zh-TW"]) == "zh-Hant", "traditional Chinese system language")
        check(AppLanguage.resolve("system", preferred: ["zh-CN"]) == "zh-Hans", "simplified Chinese system language")
        check(AppLanguage.resolve("ja", preferred: ["de-DE"]) == "ja", "manual language overrides system")
        check(AppLanguage.resolve("invalid", preferred: ["it-IT"]) == "en", "unsupported language falls back to English")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Resources/Localizable.xcstrings"))) as! [String: Any]
        let entries = catalog["strings"] as! [String: [String: Any]]
        for language in AppLanguage.supported {
            let bundles = [appBundle, finderBundle].map { AppLanguage.bundle(language: language, in: $0) }
            check(bundles.allSatisfy { $0.bundlePath.hasSuffix(language + ".lproj") }, "host and Finder localization: " + language)
            check(bundles.allSatisfy { bundle in entries.allSatisfy { key, entry in
                guard let localizations = entry["localizations"] as? [String: [String: Any]],
                      let unit = localizations[language]?["stringUnit"] as? [String: String],
                      let value = unit["value"], !value.isEmpty else { return false }
                return bundle.localizedString(forKey: key, value: nil, table: nil) == value
            } }, "host and Finder compiled translations match catalog: " + language)
        }
        let legacy = "{\"enabled\":true,\"chinese\":true,\"directories\":[{\"id\":\"legacy\",\"name\":\"My Folder\",\"value\":\"/tmp\",\"content\":\"\"}]}"
        let migrated = SuperRightClickIPC.decode(SuperRightClickConfiguration.self, from: legacy)
        check(migrated?.enabled == true && migrated?.language == "system" && migrated?.directories.first?.id == "legacy", "language migration preserves existing Finder configuration")
        var localizedConfig = SuperRightClickConfiguration()
        localizedConfig.language = "fr"
        check(SuperRightClickIPC.decode(SuperRightClickConfiguration.self, from: SuperRightClickIPC.encode(localizedConfig))?.language == "fr", "Finder IPC preserves chosen language")
        for ext in ["docx", "xlsx"] {
            let data = try SuperRightClickTemplates.data(for: .init(name: ext, value: ext), resourceDirectory: root.appendingPathComponent("Resources/FileTemplates"))
            check(data.starts(with: [0x50, 0x4b]), "real Office archive: " + ext)
        }
        let cfg = SuperRightClickConfiguration.initial(home: dir)
        let raw = SuperRightClickIPC.encode(cfg)
        check(SuperRightClickIPC.decode(SuperRightClickConfiguration.self, from: raw) == cfg, "Finder configuration round trip")
        check(SuperRightClickIPC.decode(SuperRightClickConfiguration.self, from: "{") == nil, "reject malformed IPC")
        check(SuperRightClickIPC.decode(SuperRightClickConfiguration.self, from: String(repeating: "x", count: 300_000)) == nil, "reject oversized IPC")
        check(RightClick.shellQuote("a'b") == "'a'\\''b'", "shell quote apostrophes")
        check(RightClick.appleScriptLiteral("a\"b\\c\n") == "\"a\\\"b\\\\c\\n\"", "AppleScript literal escaping")
        let rule = InputRule(id: "test.app", name: "Test", path: "/Applications/Test.app", sourceID: "zh")
        let inputSuite = "onetool-input-checks-" + UUID().uuidString
        let inputDefaults = UserDefaults(suiteName: inputSuite)!
        defer { inputDefaults.removePersistentDomain(forName: inputSuite) }
        inputDefaults.set(true, forKey: "input.enabled")
        inputDefaults.set("zh", forKey: "input.fallback")
        inputDefaults.set(false, forKey: "input.caps")
        inputDefaults.set(try JSONEncoder().encode([rule]), forKey: "input.rules")
        let restoredInputs = InputSources(defaults: inputDefaults)
        check(restoredInputs.enabled && restoredInputs.fallback == "zh" && !restoredInputs.clearCapsLock && restoredInputs.rules == [rule], "startup restores all saved input settings without overwriting them")
        restoredInputs.rules[0].sourceID = "en"
        let editedInputs = InputSources(defaults: inputDefaults)
        check(editedInputs.rules.first?.sourceID == "en", "edited per-app input source survives restart")
        restoredInputs.rules.removeAll()
        check(InputSources(defaults: inputDefaults).rules.isEmpty, "removed per-app rule stays removed after restart")
        check(InputSources.target(bundleID: "test.app", rules: [rule], fallback: "en", available: ["zh", "en"]) == "zh", "per-app input source priority")
        check(InputSources.target(bundleID: "other", rules: [rule], fallback: "en", available: ["zh", "en"]) == "en", "global input source fallback")
        check(InputSources.target(bundleID: "test.app", rules: [rule], fallback: "en", available: ["en"]) == nil, "unavailable source never switches to unrelated fallback")
        let system = InputRule(id: "test.app", name: "Test", path: "", sourceID: "")
        check(InputSources.target(bundleID: "test.app", rules: [system], fallback: "en", available: ["en"]) == nil, "per-app follow system overrides global")
        check(BrightnessSupport.readRequestPacket(code: 0x10) == [0x82, 0x01, 0x10, 0xfd], "DDC read request bytes")
        let packet = BrightnessSupport.writePacket(code: 0x10, value: 50)
        check(packet == [0x84, 0x03, 0x10, 0x00, 0x32, 0x9a], "DDC write request bytes")
        var reply: [UInt8] = [0x6e, 0x88, 0x02, 0, 0x10, 0, 0, 100, 0, 50]
        reply.append(reply.reduce(UInt8(0x50), ^))
        check(BrightnessSupport.parseReply(reply, code: 0x10)?.current == 50, "DDC valid reply")
        reply[3] = 1; reply[10] = reply[0..<10].reduce(UInt8(0x50), ^)
        check(BrightnessSupport.parseReply(reply, code: 0x10) == nil, "DDC error result rejected")
        check(BrightnessSupport.ddcCommandDelay(nowMicroseconds: 120_000, lastCommandEndMicroseconds: 100_000) == 30_000, "DDC minimum pacing")
        let assignments = BrightnessSupport.assignServices(scores: [(0, 1, 10), (0, 2, 2), (1, 1, 9), (1, 2, 8)])
        check(assignments[0] == 1 && assignments[1] == 2, "multi-display routes remain distinct")
        let defaults = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("awake.") }
        defer {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("awake.") { UserDefaults.standard.removeObject(forKey: key) }
            defaults.forEach { UserDefaults.standard.set($0.value, forKey: $0.key) }
        }
        let awake = KeepAwake()
        awake.onAC = false; awake.onBattery = false
        awake.preventSystem = true; awake.preventDisplay = false; awake.preventDisk = false; awake.preventForcedSleep = false
        awake.start(minutes: 0.002)
        check(awake.isActive && awake.error == nil && awake.endDate != nil, "real IOPM assertion starts")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(!awake.isActive && awake.endDate == nil, "timer releases real IOPM assertion")
        awake.start(); check(awake.isActive && awake.endDate == nil && awake.durationMinutes == nil, "indefinite awake session")
        awake.stop(); check(!awake.isActive, "manual stop releases session")
        awake.start(minutes: 480)
        check(awake.isActive && awake.durationMinutes == 480 && abs((awake.endDate?.timeIntervalSinceNow ?? 0) - 28800) < 2, "eight-hour session has the requested deadline")
        awake.preventDisk = true
        check(awake.durationMinutes == 480 && abs((awake.endDate?.timeIntervalSinceNow ?? 0) - 28800) < 2, "configuration change preserves duration selection and deadline")
        awake.stop()
        print("PASS: \(count) checks")
        if CommandLine.arguments.contains("--hardware") {
            print("INPUT SOURCES: " + InputSourceSelection.availableReadings().map { "\($0.name)=\($0.id)" }.joined(separator: ", "))
            if let original = InputSourceSelection.currentSourceID(),
               let alternative = InputSourceSelection.availableReadings().first(where: { $0.id != original }) {
                let inputs = InputSources()
                inputs.clearCapsLock = false
                inputs.fallback = alternative.id
                inputs.enabled = true
                inputs.scheduleSwitch()
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                let actual = InputSourceSelection.currentSourceID()
                inputs.enabled = false
                let restored = InputSourceSelection.select(sourceID: original)
                print("INPUT SWITCH: requested=\(alternative.id) actual=\(actual ?? "nil") restored=\(restored)")
                check(actual == alternative.id && restored, "real delayed default input selection and restore")
            }
            if let keyboard = KeyboardLightBridge() {
                let original = keyboard.brightness()
                let wasAutomatic = keyboard.autoBrightness
                if wasAutomatic == true { _ = keyboard.setAutoBrightness(false) }
                let requested = max(0, min(1, original + (original > 0.8 ? -0.04 : 0.04)))
                let ok = keyboard.setBrightness(requested)
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                let actual = keyboard.brightness()
                let restored = keyboard.setBrightness(original)
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                print("KEYBOARD: set=\(ok) original=\(original) requested=\(requested) actual=\(actual) restored=\(restored) final=\(keyboard.brightness())")
                if let wasAutomatic { _ = keyboard.setAutoBrightness(wasAutomatic) }
            } else { print("KEYBOARD: NOT RUN - no supported built-in backlight") }
            let displays = Displays()
            let deadline = Date().addingTimeInterval(20)
            while displays.scanning && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            for screen in displays.screens { print("DISPLAY: \(screen.name) id=\(screen.id) method=\(screen.method.rawValue) level=\(screen.level) readable=\(screen.readable)") }
            func gamma(_ id: UInt32) -> [Float]? {
                let count = min(CGDisplayGammaTableCapacity(id), 4096)
                guard count > 0 else { return nil }
                var r = [Float](repeating: 0, count: Int(count)), g = r, b = r; var actual: UInt32 = 0
                guard CGGetDisplayTransferByTable(id, count, &r, &g, &b, &actual) == .success else { return nil }
                return Array(r.prefix(Int(actual))) + Array(g.prefix(Int(actual))) + Array(b.prefix(Int(actual)))
            }
            func near(_ lhs: [Float], _ rhs: [Float], factor: Float = 1) -> Bool {
                lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { abs($0 - $1 * factor) < 0.003 }
            }
            if let screen = displays.screens.first, let before = gamma(screen.id) {
                let other = displays.screens.dropFirst().first
                let otherBefore = other.flatMap { gamma($0.id) }
                displays.preferSoftware(screen.key, enabled: true)
                while displays.scanning && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
                displays.set(screen.id, level: 0.85)
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                let dimmed = gamma(screen.id)
                check(dimmed.map { near($0, before, factor: 0.85) } ?? false, "real per-display software dimming")
                if let other, let otherBefore, let otherAfter = gamma(other.id) {
                    check(near(otherAfter, otherBefore), "software dimming leaves other display unchanged")
                }
                displays.stop()
                let restored = gamma(screen.id)
                check(restored.map { near($0, before) } ?? false, "exact gamma restoration on stop")
                UserDefaults.standard.removeObject(forKey: "display.software")
            } else { displays.stop(); print("SOFTWARE DIMMING: NOT RUN - no readable gamma table") }
        }
        print("PASS: \(count) total checks")
    }
}
