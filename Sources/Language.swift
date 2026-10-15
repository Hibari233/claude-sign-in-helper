import AppKit

/// The app's own language choice. It's stored like System Settings' per-app language (`AppleLanguages`
/// in this app's preferences), and macOS applies it the next time the app opens.
enum AppLanguage {
    /// Each language shown by its own name, as macOS does.
    static let choices: [(code: String, name: String)] = [("en", "English"), ("ja", "日本語"), ("zh-Hans", "简体中文"), ("fr", "Français")]

    /// The saved choice, or nil when the app follows the system.
    static var selected: String? {
        guard let domain = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: domain)?["AppleLanguages"] as? [String] else { return nil }
        return languages.first
    }

    static func isSelected(_ code: String?) -> Bool {
        guard let code else { return selected == nil }
        return selected == code || selected?.hasPrefix(code + "-") == true
    }

    static func select(_ code: String?) {
        if let code { UserDefaults.standard.set([code], forKey: "AppleLanguages") }
        else { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
    }

    /// The language the app would use for a choice, so a restart is only offered when the text would change.
    static func resolved(_ code: String?) -> String? {
        let preferences = code.map { [$0] }
            ?? UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: preferences).first
    }
    static var current: String? { Bundle.main.preferredLocalizations.first }

    /// Opens a fresh copy of the app, then quits this one.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async { if error == nil { NSApp.terminate(nil) } }
        }
    }
}
