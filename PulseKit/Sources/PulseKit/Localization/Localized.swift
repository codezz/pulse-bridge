import Foundation

/// Looks up a module's text in the language the app runs in (its per-app language or the phone's),
/// or in an explicit language. Picks the `.lproj` inside the module bundle, so tests and the Mac tool
/// stay in English whatever the Mac's language is.
public enum Localized {
    /// The app's language: the first of the main bundle's localizations the user prefers.
    public static var appLanguage: String { Bundle.main.preferredLocalizations.first ?? "en" }

    public static func string(_ key: String.LocalizationValue, bundle: Bundle, language: String? = nil) -> String {
        let code = language ?? appLanguage
        let lproj = bundle.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
            ?? bundle.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
            ?? bundle
        return String(localized: key, bundle: lproj, locale: Locale(identifier: code))
    }
}

/// This module's text (see `Localized`).
func L(_ key: String.LocalizationValue, language: String? = nil) -> String {
    Localized.string(key, bundle: .module, language: language)
}
