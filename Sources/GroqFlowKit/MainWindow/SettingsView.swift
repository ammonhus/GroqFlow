import SwiftUI
import AVFoundation

struct SettingsView: View {
    let model: MainWindowModel
    @ObservedObject private var settings: SettingsStore

    @State private var keyField = ""
    @State private var validation: ValidationState = .idle
    @State private var micDevices: [MicDevice] = []

    init(model: MainWindowModel) {
        self.model = model
        _settings = ObservedObject(wrappedValue: model.settings)
    }

    enum ValidationState: Equatable {
        case idle, checking, valid, invalid
    }

    struct MicDevice: Identifiable, Hashable {
        let id: String
        let name: String
    }

    struct Language: Identifiable, Hashable {
        let id: String   // ISO 639-1 code
        let name: String
    }

    var body: some View {
        Form {
            generalSection
            languageSection
            systemSection
            formattingSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Settings")
        .onAppear {
            keyField = settings.apiKey ?? ""
            loadMicDevices()
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section("General") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SecureField("Groq API key", text: $keyField)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: keyField) { _, _ in
                            if validation != .idle { validation = .idle }
                        }
                    Button("Validate", action: validate)
                        .disabled(keyField.trimmingCharacters(in: .whitespaces).isEmpty
                                  || validation == .checking)
                }
                validationLabel
            }

            Picker("Microphone", selection: $settings.micDeviceUID) {
                Text("System Default").tag(String?.none)
                ForEach(micDevices) { device in
                    Text(device.name).tag(String?.some(device.id))
                }
            }

            Picker("Dictation shortcut", selection: $settings.hotkey) {
                ForEach(HotkeyChoice.allCases, id: \.self) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
        }
    }

    @ViewBuilder
    private var validationLabel: some View {
        switch validation {
        case .idle:
            Text("Stored securely in your macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking...").font(.caption).foregroundStyle(.secondary)
            }
        case .valid:
            Label("Key is valid", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .invalid:
            Label("Invalid key", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Languages

    private var languageSection: some View {
        Section("Languages") {
            Toggle("Auto-detect spoken language", isOn: $settings.autoDetectLanguage)
            if !settings.autoDetectLanguage {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              alignment: .leading, spacing: 4) {
                        ForEach(Self.languages) { language in
                            Toggle(language.name, isOn: languageBinding(language.id))
                                .toggleStyle(.checkbox)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 180)
            }
        }
    }

    private func languageBinding(_ code: String) -> Binding<Bool> {
        Binding(
            get: { settings.languages.contains(code) },
            set: { isOn in
                if isOn {
                    if !settings.languages.contains(code) { settings.languages.append(code) }
                } else {
                    settings.languages.removeAll { $0 == code }
                }
            })
    }

    // MARK: - System

    private var systemSection: some View {
        Section("System") {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            Toggle("Show Flow Bar", isOn: $settings.showFlowBar)
            Toggle("Play sounds", isOn: $settings.soundsEnabled)
        }
    }

    // MARK: - Formatting

    private var formattingSection: some View {
        Section("Formatting") {
            Toggle("Smart formatting", isOn: $settings.smartFormatting)
            Toggle("Context awareness", isOn: $settings.contextAwareness)
            Toggle("Type instead of paste", isOn: $settings.typeInsteadOfPaste)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
            Text("GroqFlow dictates anywhere on your Mac using Groq Whisper and Llama. Hold your shortcut, speak, release.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short ?? "1.0"
    }

    // MARK: - Actions

    private func validate() {
        let key = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        validation = .checking
        Task {
            let ok = await (model.onValidateKey?(key) ?? false)
            if ok {
                settings.apiKey = key
                validation = .valid
            } else {
                validation = .invalid
            }
        }
    }

    private func loadMicDevices() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified)
        micDevices = session.devices.map { MicDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    // Common Whisper-supported languages (ISO 639-1).
    static let languages: [Language] = [
        Language(id: "en", name: "English"), Language(id: "es", name: "Spanish"),
        Language(id: "fr", name: "French"), Language(id: "de", name: "German"),
        Language(id: "it", name: "Italian"), Language(id: "pt", name: "Portuguese"),
        Language(id: "nl", name: "Dutch"), Language(id: "ru", name: "Russian"),
        Language(id: "zh", name: "Chinese"), Language(id: "ja", name: "Japanese"),
        Language(id: "ko", name: "Korean"), Language(id: "ar", name: "Arabic"),
        Language(id: "hi", name: "Hindi"), Language(id: "tr", name: "Turkish"),
        Language(id: "pl", name: "Polish"), Language(id: "sv", name: "Swedish"),
        Language(id: "da", name: "Danish"), Language(id: "no", name: "Norwegian"),
        Language(id: "fi", name: "Finnish"), Language(id: "cs", name: "Czech"),
        Language(id: "el", name: "Greek"), Language(id: "he", name: "Hebrew"),
        Language(id: "th", name: "Thai"), Language(id: "vi", name: "Vietnamese"),
        Language(id: "id", name: "Indonesian"), Language(id: "ms", name: "Malay"),
        Language(id: "uk", name: "Ukrainian"), Language(id: "ro", name: "Romanian"),
        Language(id: "hu", name: "Hungarian"), Language(id: "bg", name: "Bulgarian"),
        Language(id: "hr", name: "Croatian"), Language(id: "sk", name: "Slovak"),
        Language(id: "ca", name: "Catalan"), Language(id: "tl", name: "Tagalog"),
        Language(id: "fa", name: "Persian"), Language(id: "ta", name: "Tamil"),
        Language(id: "ur", name: "Urdu"), Language(id: "bn", name: "Bengali"),
        Language(id: "mr", name: "Marathi"), Language(id: "sw", name: "Swahili")
    ]
}
