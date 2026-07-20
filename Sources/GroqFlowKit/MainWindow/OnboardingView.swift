import SwiftUI
import AppKit
import Combine

struct OnboardingView: View {
    let model: MainWindowModel
    let onFinish: () -> Void

    @State private var step: Step = .welcome
    @State private var apiValidated = false

    init(model: MainWindowModel, onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    enum Step: Int, CaseIterable {
        case welcome, apiKey, permissions, micTest, practice
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.top, 20)
                .padding(.horizontal, 24)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            navBar
                .padding(16)
        }
        .frame(minWidth: 820, minHeight: 520)
        .onAppear {
            apiValidated = !(model.settings.apiKey ?? "").isEmpty
        }
    }

    // MARK: - Progress

    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(height: 4)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            WelcomeStep()
        case .apiKey:
            ApiKeyStep(model: model, validated: $apiValidated)
        case .permissions:
            PermissionsStep()
        case .micTest:
            MicTestStep(micUID: model.settings.micDeviceUID)
        case .practice:
            PracticeStep(shortcut: model.settings.hotkey.displayName)
        }
    }

    // MARK: - Navigation

    private var navBar: some View {
        HStack {
            if step != .welcome {
                Button("Back", action: back)
            }
            Spacer()
            Button(step == .practice ? "Finish" : "Continue", action: next)
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
        }
    }

    private var canContinue: Bool {
        switch step {
        case .apiKey: return apiValidated
        default: return true
        }
    }

    private func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func next() {
        if step == .practice {
            onFinish()
            return
        }
        guard let following = Step(rawValue: step.rawValue + 1) else { return }
        step = following
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Welcome to GroqFlow")
                .font(.largeTitle.weight(.semibold))
            Text("Dictate anywhere on your Mac. Hold your shortcut, speak naturally, and GroqFlow transcribes, cleans up, and types it in for you.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .padding(40)
    }
}

// MARK: - API key

private struct ApiKeyStep: View {
    let model: MainWindowModel
    @Binding var validated: Bool

    @State private var keyField = ""
    @State private var checking = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Connect your Groq API key")
                .font(.title.weight(.semibold))
            Text("GroqFlow uses your own Groq account. Paste your API key below and validate it to continue. It is stored in your macOS Keychain.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            HStack {
                SecureField("gsk_...", text: $keyField)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onChange(of: keyField) { _, _ in
                        validated = false
                        failed = false
                    }
                Button("Validate", action: validate)
                    .disabled(keyField.trimmingCharacters(in: .whitespaces).isEmpty || checking)
            }

            statusLabel
        }
        .padding(40)
        .onAppear { keyField = model.settings.apiKey ?? "" }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if checking {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking...").foregroundStyle(.secondary)
            }
        } else if validated {
            Label("Key is valid", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if failed {
            Label("That key did not work", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func validate() {
        let key = keyField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        checking = true
        failed = false
        Task {
            let ok = await (model.onValidateKey?(key) ?? false)
            checking = false
            if ok {
                model.settings.apiKey = key
                validated = true
            } else {
                validated = false
                failed = true
            }
        }
    }
}

// MARK: - Permissions

private struct PermissionsStep: View {
    @State private var mic = false
    @State private var input = false
    @State private var accessibility = false

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Text("Grant permissions")
                .font(.title.weight(.semibold))
            Text("GroqFlow needs three macOS permissions. Status updates automatically as you grant them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            VStack(spacing: 10) {
                PermissionRow(title: "Microphone",
                              detail: "Record your voice.",
                              granted: mic,
                              action: grantMic)
                PermissionRow(title: "Input Monitoring",
                              detail: "Detect your dictation shortcut.",
                              granted: input,
                              action: grantInput)
                PermissionRow(title: "Accessibility",
                              detail: "Type text into other apps.",
                              granted: accessibility,
                              action: grantAccessibility)
            }
            .frame(maxWidth: 480)
        }
        .padding(40)
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        mic = Permissions.micGranted
        input = Permissions.inputMonitoringGranted
        accessibility = Permissions.accessibilityGranted
    }

    private func grantMic() {
        Task {
            _ = await Permissions.requestMic()
            refresh()
        }
    }

    private func grantInput() {
        Permissions.requestInputMonitoring()
        Permissions.openSettingsPane(.inputMonitoring)
    }

    private func grantAccessibility() {
        Permissions.requestAccessibility()
        Permissions.openSettingsPane(.accessibility)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Grant", action: action)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Mic test

private struct MicTestStep: View {
    let micUID: String?

    @StateObject private var recorder = AudioRecorder()
    @State private var failed = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Test your microphone")
                .font(.title.weight(.semibold))
            Text("Speak and watch the meter respond.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if failed {
                Label("Could not start the microphone. Check the permission and device.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            LevelMeter(level: recorder.level)
                .frame(width: 360, height: 60)
        }
        .padding(40)
        .onAppear {
            recorder.setPreferredDevice(uid: micUID)
            do {
                try recorder.start()
            } catch {
                failed = true
            }
        }
        .onDisappear {
            recorder.cancel()
        }
    }
}

private struct LevelMeter: View {
    let level: Float
    private let barCount = 24

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 4
            let barWidth = max(2, (geo.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(barColor(index))
                        .frame(width: barWidth, height: barHeight(index, maxHeight: geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func barHeight(_ index: Int, maxHeight: CGFloat) -> CGFloat {
        let fraction = CGFloat(index + 1) / CGFloat(barCount)
        let active = CGFloat(level) >= fraction
        let base: CGFloat = 6
        return active ? max(base, maxHeight * fraction) : base
    }

    private func barColor(_ index: Int) -> Color {
        let fraction = CGFloat(index + 1) / CGFloat(barCount)
        return CGFloat(level) >= fraction ? Color.accentColor : Color.secondary.opacity(0.25)
    }
}

// MARK: - Practice

private struct PracticeStep: View {
    let shortcut: String
    @State private var text = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Try it out")
                .font(.title.weight(.semibold))
            Text("Click into the box below, then hold \(shortcut) and speak. Release to see your words appear.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            TextEditor(text: $text)
                .font(.body)
                .frame(width: 440, height: 160)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            Text("You are all set. Click Finish to start using GroqFlow.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}
