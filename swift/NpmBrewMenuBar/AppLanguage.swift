import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case french
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .french:
            return "Francais"
        case .english:
            return "English"
        }
    }

    var shortLabel: String {
        switch self {
        case .french:
            return "FR"
        case .english:
            return "EN"
        }
    }
}

@MainActor
final class LanguageManager: ObservableObject {
    private enum DefaultsKey {
        static let appLanguage = "appLanguage"
    }

    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: DefaultsKey.appLanguage)
        }
    }

    init() {
        if
            let rawValue = UserDefaults.standard.string(forKey: DefaultsKey.appLanguage),
            let language = AppLanguage(rawValue: rawValue)
        {
            currentLanguage = language
        } else {
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
            currentLanguage = preferred.hasPrefix("fr") ? .french : .english
        }
    }

    func text(_ french: String, _ english: String) -> String {
        switch currentLanguage {
        case .french:
            return french
        case .english:
            return english
        }
    }
}

enum L {
    private static var currentLanguage: AppLanguage {
        if
            let rawValue = UserDefaults.standard.string(forKey: "appLanguage"),
            let language = AppLanguage(rawValue: rawValue)
        {
            return language
        }

        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("fr") ? .french : .english
    }

    static func text(_ french: String, _ english: String) -> String {
        switch currentLanguage {
        case .french:
            return french
        case .english:
            return english
        }
    }
}
