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

    @UserDefault(key: "speakin_model", defaultValue: "qwen-omni-turbo-realtime-latest")
    var model: String

    @UserDefault(key: "speakin_language", defaultValue: "zh-CN")
    var language: String

    @UserDefault(key: "speakin_launchAtLogin", defaultValue: false)
    var launchAtLogin: Bool

    var languageDisplayName: String {
        switch language {
        case "zh-CN": return "简体中文"
        case "zh-TW": return "繁體中文"
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
        case "zh-TW": return "繁體中文"
        case "en":    return "English"
        case "ja":    return "日本語"
        case "ko":    return "한국어"
        default:      return "简体中文"
        }
    }

    private init() {}
}
