import Foundation

/// The exercises the app suggests at first setup, known in every language the app has.
public enum ChallengeDefaults {
    private static let keys: [String.LocalizationValue] = ["Push-ups", "Squats"]

    /// "Push-ups", "Squats" / "Flotări", "Genuflexiuni" (the app's language by default).
    public static func exerciseNames(language: String? = nil) -> [String] {
        keys.map { L($0, language: language) }
    }

    /// A default exercise named in any language ("Push-ups" or "flotări") becomes its name in
    /// `language`; any other name is returned as it is.
    public static func name(_ name: String, in language: String?) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let languages = Bundle.module.localizations.filter { $0 != "Base" }
        for index in keys.indices {
            let known = languages.map { exerciseNames(language: $0)[index] }
            if known.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return exerciseNames(language: language)[index]
            }
        }
        return name
    }
}
