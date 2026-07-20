import Foundation
import Combine

// UserDefaults-backed settings. Every published property persists on didSet.
// The API key is the exception: it is stored in the Keychain, not UserDefaults.
@MainActor
public final class SettingsStore: ObservableObject {
    // Keychain coordinates for the Groq API key.
    public static let keychainService = "com.ammon.groqflow"
    public static let keychainAccount = "groq-api-key"

    private let defaults: UserDefaults
    // While true (during init load) didSet observers skip persistence.
    private var loading = true

    @Published public var hotkey: HotkeyChoice = .rightOption {
        didSet { persist() }
    }
    @Published public var languages: [String] = [] {
        didSet { persist() }
    }
    @Published public var autoDetectLanguage: Bool = true {
        didSet { persist() }
    }
    @Published public var micDeviceUID: String? = nil {
        didSet { persist() }
    }
    @Published public var launchAtLogin: Bool = false {
        didSet {
            persist()
            guard !loading else { return }
            LaunchAtLogin.set(launchAtLogin)
        }
    }
    @Published public var showFlowBar: Bool = true {
        didSet { persist() }
    }
    @Published public var soundsEnabled: Bool = true {
        didSet { persist() }
    }
    @Published public var smartFormatting: Bool = true {
        didSet { persist() }
    }
    @Published public var contextAwareness: Bool = true {
        didSet { persist() }
    }
    @Published public var typeInsteadOfPaste: Bool = false {
        didSet { persist() }
    }
    @Published public var stylePresets: [StyleCategory: StylePreset] = SettingsStore.defaultPresets {
        didSet { persist() }
    }
    @Published public var onboardingComplete: Bool = false {
        didSet { persist() }
    }

    // Keychain-backed. Setting nil or empty removes the stored key.
    public var apiKey: String? {
        get { KeychainHelper.get(service: Self.keychainService, account: Self.keychainAccount) }
        set {
            if let value = newValue, !value.isEmpty {
                _ = KeychainHelper.set(value, service: Self.keychainService, account: Self.keychainAccount)
            } else {
                KeychainHelper.delete(service: Self.keychainService, account: Self.keychainAccount)
            }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        loading = false
    }

    // MARK: - Defaults

    static let defaultPresets: [StyleCategory: StylePreset] = [
        .personalMessaging: .casual,
        .workMessaging: .casual,
        .email: .formal,
        .code: .casual,
        .other: .formal
    ]

    private enum Keys {
        static let hotkey = "groqflow.hotkey"
        static let languages = "groqflow.languages"
        static let autoDetectLanguage = "groqflow.autoDetectLanguage"
        static let micDeviceUID = "groqflow.micDeviceUID"
        static let launchAtLogin = "groqflow.launchAtLogin"
        static let showFlowBar = "groqflow.showFlowBar"
        static let soundsEnabled = "groqflow.soundsEnabled"
        static let smartFormatting = "groqflow.smartFormatting"
        static let contextAwareness = "groqflow.contextAwareness"
        static let typeInsteadOfPaste = "groqflow.typeInsteadOfPaste"
        static let stylePresets = "groqflow.stylePresets"
        static let onboardingComplete = "groqflow.onboardingComplete"
    }

    // MARK: - Load

    private func load() {
        if let raw = defaults.string(forKey: Keys.hotkey), let choice = HotkeyChoice(rawValue: raw) {
            hotkey = choice
        }
        if defaults.object(forKey: Keys.languages) != nil {
            languages = defaults.stringArray(forKey: Keys.languages) ?? []
        }
        autoDetectLanguage = boolValue(Keys.autoDetectLanguage, default: true)
        micDeviceUID = defaults.string(forKey: Keys.micDeviceUID)
        launchAtLogin = boolValue(Keys.launchAtLogin, default: false)
        showFlowBar = boolValue(Keys.showFlowBar, default: true)
        soundsEnabled = boolValue(Keys.soundsEnabled, default: true)
        smartFormatting = boolValue(Keys.smartFormatting, default: true)
        contextAwareness = boolValue(Keys.contextAwareness, default: true)
        typeInsteadOfPaste = boolValue(Keys.typeInsteadOfPaste, default: false)
        stylePresets = loadPresets()
        onboardingComplete = boolValue(Keys.onboardingComplete, default: false)
    }

    private func boolValue(_ key: String, default def: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? def : defaults.bool(forKey: key)
    }

    private func loadPresets() -> [StyleCategory: StylePreset] {
        var result = Self.defaultPresets
        if let data = defaults.data(forKey: Keys.stylePresets),
           let raw = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, value) in raw {
                if let category = StyleCategory(rawValue: key), let preset = StylePreset(rawValue: value) {
                    result[category] = preset
                }
            }
        }
        return result
    }

    // MARK: - Persist

    private func persist() {
        guard !loading else { return }

        defaults.set(hotkey.rawValue, forKey: Keys.hotkey)
        defaults.set(languages, forKey: Keys.languages)
        defaults.set(autoDetectLanguage, forKey: Keys.autoDetectLanguage)
        if let uid = micDeviceUID {
            defaults.set(uid, forKey: Keys.micDeviceUID)
        } else {
            defaults.removeObject(forKey: Keys.micDeviceUID)
        }
        defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        defaults.set(showFlowBar, forKey: Keys.showFlowBar)
        defaults.set(soundsEnabled, forKey: Keys.soundsEnabled)
        defaults.set(smartFormatting, forKey: Keys.smartFormatting)
        defaults.set(contextAwareness, forKey: Keys.contextAwareness)
        defaults.set(typeInsteadOfPaste, forKey: Keys.typeInsteadOfPaste)
        defaults.set(onboardingComplete, forKey: Keys.onboardingComplete)

        var rawPresets: [String: String] = [:]
        for (category, preset) in stylePresets {
            rawPresets[category.rawValue] = preset.rawValue
        }
        if let data = try? JSONEncoder().encode(rawPresets) {
            defaults.set(data, forKey: Keys.stylePresets)
        }
    }
}
