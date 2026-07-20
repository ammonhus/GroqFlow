import SwiftUI

// Visual styling shared across the flow bar.
enum FlowBarStyle {
    static let background = Color.black.opacity(0.82)
    static let recordAccent = Color.white.opacity(0.95)
    static let commandAccent = Color(red: 0.64, green: 0.46, blue: 0.99)
}

// Dark capsule chrome with optional accent border and a soft shadow.
struct FlowBarCapsule<Content: View>: View {
    var borderColor: Color = .clear
    var borderWidth: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(Capsule().fill(FlowBarStyle.background))
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: borderWidth))
            .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 2)
    }
}

// Processing state: dark capsule with a sweeping highlight.
struct ProcessingShimmer: View {
    @State private var phase: CGFloat = -0.7

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Capsule()
                .fill(FlowBarStyle.background)
                .overlay(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.45), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: w * 0.45)
                    .offset(x: phase * w)
                )
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 2)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                phase = 1.3
            }
        }
    }
}

// Root content of the flow bar panel. Observes dictation state + flash message.
struct FlowBarView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var model: FlowBarModel

    var body: some View {
        ZStack {
            Color.clear.allowsHitTesting(false)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: transitionKey)
    }

    // Changes only on visual state transitions, so the spring above does not
    // fire on every audio-level update while recording.
    private var transitionKey: String {
        if let message = model.flashMessage { return "flash:" + message }
        switch appState.dictationState {
        case .idle: return "idle"
        case .recording(let mode): return "recording:\(mode)"
        case .processing: return "processing"
        case .inserting: return "inserting"
        }
    }

    @ViewBuilder
    private var content: some View {
        if let message = model.flashMessage {
            flashBar(message)
        } else {
            switch appState.dictationState {
            case .idle:
                idlePill
            case .recording(let mode):
                recordingBar(isCommand: mode == .command)
            case .processing, .inserting:
                processingBar
            }
        }
    }

    // MARK: - States

    private var idlePill: some View {
        Capsule()
            .fill(Color.white.opacity(0.28))
            .frame(width: 20, height: 6)
            .contentShape(Capsule())
            .onTapGesture { model.onIdle?() }
            .transition(.opacity)
    }

    // Just the sound-wave visualization. Cancel is Esc; stop is a press of the
    // dictation key, so the bar carries no buttons.
    private func recordingBar(isCommand: Bool) -> some View {
        let accent = isCommand ? FlowBarStyle.commandAccent : FlowBarStyle.recordAccent
        return FlowBarCapsule(
            borderColor: isCommand ? FlowBarStyle.commandAccent : .clear,
            borderWidth: isCommand ? 1 : 0
        ) {
            WaveformView(
                level: CGFloat(max(0, min(1, appState.audioLevel))),
                color: accent
            )
            .frame(width: 92, height: 15)
            .padding(.horizontal, 14)
            .frame(height: 26)
        }
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private var processingBar: some View {
        ProcessingShimmer()
            .frame(width: 66, height: 24)
            .transition(.opacity)
    }

    private func flashBar(_ message: String) -> some View {
        FlowBarCapsule {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(height: 40)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

}
