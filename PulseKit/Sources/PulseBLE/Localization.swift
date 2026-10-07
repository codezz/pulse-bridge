import Foundation
import PulseKit

/// This module's text (see `Localized`).
func L(_ key: String.LocalizationValue, language: String? = nil) -> String {
    Localized.string(key, bundle: .module, language: language)
}
