import Foundation
import Combine

// Central observable state. DictationController is the only writer;
// FlowBar, StatusItem, and MainWindow observe.
// audioLevel is bridged from AudioRecorder.level by DictationController.
@MainActor
public final class AppState: ObservableObject {
    @Published public var dictationState: DictationState = .idle
    @Published public var audioLevel: Float = 0
    @Published public var lastError: String?
    @Published public var lastTranscript: TranscriptRecord?

    public init() {}
}
