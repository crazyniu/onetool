// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Shared by the app and Finder extension. English is the fallback for unsupported languages.
enum AppLanguage {
    static let preferenceKey = "app.language"
    static let supported = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "fr", "de", "es"]
    static let names = ["en": "English", "zh-Hans": "简体中文", "zh-Hant": "繁體中文",
                        "ja": "日本語", "ko": "한국어", "fr": "Français", "de": "Deutsch", "es": "Español"]

    static func resolve(_ selection: String, preferred: [String] = Locale.preferredLanguages) -> String {
        if supported.contains(selection) { return selection }
        return Bundle.preferredLocalizations(from: supported, forPreferences: preferred).first ?? "en"
    }
    static var current: String { resolve(UserDefaults.standard.string(forKey: preferenceKey) ?? "system") }
    static var locale: Locale { Locale(identifier: current) }
    static func bundle(language: String? = nil, in bundle: Bundle = .main) -> Bundle {
        let code = language.map { resolve($0) } ?? current
        guard let path = bundle.path(forResource: code, ofType: "lproj"), let localized = Bundle(path: path) else { return bundle }
        return localized
    }
}

/// Explicit bundle lookup also updates AppKit menus and the separately hosted status panel.
func L(_ key: String, language: String? = nil) -> String {
    AppLanguage.bundle(language: language).localizedString(forKey: key, value: key, table: nil)
}

func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: AppLanguage.locale, arguments: arguments)
}
