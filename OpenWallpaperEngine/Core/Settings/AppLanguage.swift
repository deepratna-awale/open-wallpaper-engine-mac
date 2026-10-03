import Foundation

/// The language the app's own text is shown in: the language chosen in Settings, else the first of
/// the system's preferred languages the app is translated into, else English (the catalog's
/// source language).
///
/// The system's languages are read from the global domain, not `Locale.preferredLanguages`: that
/// list starts with the app domain's `AppleLanguages`, which can hold a language the setting no
/// longer names (a value left by an earlier choice or a copied preferences file), and then an
/// English Mac shows the app in that language.
enum AppLanguage {
    static let fallback = "en"

    /// The localization to use, among `available` (`Bundle.main.localizations`).
    static func resolve(setting: GSLocalization, systemPreferred: [String], available: [String]) -> String {
        let localizations = available.filter { $0 != "Base" }
        if let chosen = setting.languageIdentifier, let match = match(chosen, in: localizations) {
            return match
        }
        for language in systemPreferred {
            if let match = match(language, in: localizations) { return match }
        }
        return fallback
    }

    /// `identifier`'s localization among `localizations`: an exact match, else the same language
    /// (and script, for Chinese).
    private static func match(_ identifier: String, in localizations: [String]) -> String? {
        if let exact = localizations.first(where: { $0.caseInsensitiveCompare(identifier) == .orderedSame }) {
            return exact
        }
        let found = Bundle.preferredLocalizations(from: localizations, forPreferences: [identifier])
        guard let first = found.first, localizations.contains(first) else { return nil }
        // `preferredLocalizations` falls back to the first localization when nothing matches.
        let wanted = Locale.Language(identifier: identifier)
        let got = Locale.Language(identifier: first)
        guard wanted.languageCode == got.languageCode else { return nil }
        return first
    }

    /// The system's preferred languages (System Settings › Language & Region), without the app's own.
    static func systemPreferredLanguages(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String] ?? []
    }

    /// The current resolution for this app.
    static func current(setting: GSLocalization) -> String {
        resolve(setting: setting, systemPreferred: systemPreferredLanguages(), available: Bundle.main.localizations)
    }

    /// `key` from the app's catalog in the current language; the key (English) when untranslated.
    static func string(_ key: String, setting: GSLocalization, bundle: Bundle = .main) -> String {
        let language = current(setting: setting)
        guard let path = bundle.path(forResource: language, ofType: "lproj"),
              let localized = Bundle(path: path) else { return key }
        return localized.localizedString(forKey: key, value: key, table: nil)
    }
}
