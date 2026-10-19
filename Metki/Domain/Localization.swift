import Foundation

/// Localizes presentation strings without changing user content or stored identifiers.
enum L10n {
    static func text(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        // Plural rules belong to the selected translation, even when the device's
        // region or preferred formatting language differs from the app language.
        let locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "ru")
        return String(format: text(key), locale: locale, arguments: arguments)
    }

    static func bytes(_ count: Int) -> String {
        format("%lld байт", count)
    }
}
