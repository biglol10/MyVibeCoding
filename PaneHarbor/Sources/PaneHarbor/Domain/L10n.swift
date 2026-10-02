import Foundation

public enum L10n {
    public static func format(_ key: String, _ values: CVarArg...) -> String {
        String(format: text(key), arguments: values)
    }
    public static func text(_ key: String) -> String {
        let chosen = UserDefaults.standard.string(forKey: "PaneHarbor.language") ?? "system"
        let language = chosen == "system" ? (Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "ko" : "en") : chosen
        #if SWIFT_PACKAGE
        let resources = Bundle.main.path(forResource: "en", ofType: "lproj") == nil ? Bundle.module : Bundle.main
        #else
        let resources = Bundle.main
        #endif
        guard let path = resources.path(forResource: language, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
