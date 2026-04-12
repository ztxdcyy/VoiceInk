import Foundation

// MARK: - UserDefault Property Wrapper

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T
    let container: UserDefaults = .standard

    var wrappedValue: T {
        get { container.object(forKey: key) as? T ?? defaultValue }
        set { container.set(newValue, forKey: key) }
    }
}

@propertyWrapper
struct OptionalUserDefault<T> {
    let key: String
    let container: UserDefaults = .standard

    var wrappedValue: T? {
        get { container.object(forKey: key) as? T }
        set {
            if let val = newValue {
                container.set(val, forKey: key)
            } else {
                container.removeObject(forKey: key)
            }
        }
    }
}

// MARK: - Settings Store

class SettingsStore {
    static let shared = SettingsStore()

    @OptionalUserDefault<String>(key: "speakin_apiKey")
    var apiKey: String?

    @UserDefault(key: "speakin_language", defaultValue: SettingsStore.detectSystemLanguage())
    var language: String

    /// Infer language from macOS system preferences, falling back to "en".
    static func detectSystemLanguage() -> String {
        let supported: [(prefixes: [String], code: String)] = [
            (["zh-Hans", "zh-CN", "zh-Hant", "zh-TW", "zh-HK"], "zh-CN"),
            (["en"], "en"),
            (["ja"], "ja"),
            (["ko"], "ko"),
        ]
        for preferred in Locale.preferredLanguages {
            for entry in supported {
                for prefix in entry.prefixes {
                    if preferred.hasPrefix(prefix) {
                        return entry.code
                    }
                }
            }
        }
        return "en"
    }

    @UserDefault(key: "speakin_launchAtLogin", defaultValue: false)
    var launchAtLogin: Bool

    var languageDisplayName: String {
        switch language {
        case "zh-CN": return "简体中文"
        case "en":    return "English"
        case "ja":    return "日本語"
        case "ko":    return "한국어"
        default:      return "简体中文"
        }
    }

    /// Language instruction fragment for the system prompt
    var languageInstruction: String {
        switch language {
        case "zh-CN": return "简体中文"
        case "en":    return "English"
        case "ja":    return "日本語"
        case "ko":    return "한국어"
        default:      return "简体中文"
        }
    }

    /// Custom trigger hotkey stored as JSON Data in UserDefaults.
    /// nil means "use the default Fn key".
    var customHotkey: UserHotkeyConfig? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "speakin_customHotkey") else { return nil }
            return try? JSONDecoder().decode(UserHotkeyConfig.self, from: data)
        }
        set {
            if let config = newValue, let data = try? JSONEncoder().encode(config) {
                UserDefaults.standard.set(data, forKey: "speakin_customHotkey")
            } else {
                UserDefaults.standard.removeObject(forKey: "speakin_customHotkey")
            }
        }
    }

    private init() {
        // Migrate legacy zh-TW setting to zh-CN
        if language == "zh-TW" {
            language = "zh-CN"
        }
        // Clean up legacy model key
        UserDefaults.standard.removeObject(forKey: "speakin_model")
    }
}
