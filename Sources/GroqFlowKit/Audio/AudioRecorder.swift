import Foundation
import Combine
import AVFoundation
import CoreAudio
import AudioToolbox

// Captures microphone audio via AVAudioEngine, converts to 16 kHz mono Int16
// in memory, and publishes a smoothed RMS level for the waveform.
@MainActor
public final class AudioRecorder: ObservableObject {
    // 0...1 smoothed RMS, published ~30 Hz for the waveform.
    @Published public private(set) var level: Float = 0
    public private(set) var isRecording: Bool = false

    private let engine = AVAudioEngine()
    private let sink = AudioSink()
    private var levelTimer: Timer?
    private var tapInstalled = false
    private var preferredDeviceUID: String?

    private let targetSampleRate = 16000
    // 10-minute hard cap on accumulated audio.
    private let maxSamples = 16000 * 600

    public init() {
        // Do NOT call engine.prepare() here: with no nodes touched yet the
        // graph is empty and AVFAudio raises an NSException
        // ("inputNode != nullptr || outputNode != nullptr").
        // start() accesses inputNode and prepares the real graph.
    }

    public func setPreferredDevice(uid: String?) {
        preferredDeviceUID = uid
    }

    public func start() throws {
        guard !isRecording else { return }

        sink.reset()
        applyInputDevice()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: Double(targetSampleRate),
                                               channels: 1,
                                               interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterUnavailable
        }

        sink.configure(converter: converter, targetFormat: targetFormat, maxSamples: maxSamples)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [sink] buffer, _ in
            sink.process(buffer)
        }
        tapInstalled = true

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            throw error
        }

        isRecording = true
        startLevelTimer()
        Log.audio.info("recording started")
    }

    // Returns 16 kHz mono 16-bit WAV, or nil if under the 0.4 s minimum.
    public func stop() -> Data? {
        guard isRecording else { return nil }
        teardown()

        let samples = sink.samples()
        let duration = AudioMath.duration(sampleCount: samples.count, sampleRate: targetSampleRate)
        guard duration >= AudioMath.minDuration else {
            Log.audio.info("recording discarded, too short")
            return nil
        }
        return WAVEncoder.wavData(fromPCM16: samples, sampleRate: targetSampleRate)
    }

    public func cancel() {
        guard isRecording else { return }
        teardown()
        sink.reset()
        Log.audio.info("recording cancelled")
    }

    public var currentDuration: TimeInterval {
        AudioMath.duration(sampleCount: sink.count, sampleRate: targetSampleRate)
    }

    // MARK: - Internals

    private func teardown() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning { engine.stop() }
        levelTimer?.invalidate()
        levelTimer = nil
        isRecording = false
        level = 0
        // Keep the engine warm for the next session.
        engine.prepare()
    }

    private func startLevelTimer() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.level = AudioMath.displayLevel(rms: self.sink.level)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    private func applyInputDevice() {
        guard let uid = preferredDeviceUID,
              let devID = AudioRecorder.deviceID(forUID: uid),
              let unit = engine.inputNode.audioUnit else { return }
        var deviceID = devID
        AudioUnitSetProperty(unit,
                             kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global,
                             0,
                             &deviceID,
                             UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var cfUID: CFString = uid as CFString
        var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPtr in
            withUnsafeMutablePointer(to: &deviceID) { devPtr -> OSStatus in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(uidPtr),
                    mInputDataSize: UInt32(MemoryLayout<CFString>.size),
                    mOutputData: UnsafeMutableRawPointer(devPtr),
                    mOutputDataSize: UInt32(MemoryLayout<AudioDeviceID>.size))
                return AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &translation)
            }
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private enum RecorderError: Error {
        case noInputDevice
        case converterUnavailable
    }

    // Pure sample-duration math, isolated for testability.
    enum AudioMath {
        static let minDuration: TimeInterval = 0.4
        static func duration(sampleCount: Int, sampleRate: Int) -> TimeInterval {
            guard sampleRate > 0 else { return 0 }
            return TimeInterval(sampleCount) / TimeInterval(sampleRate)
        }

        // Maps raw normalized RMS (which sits near the bottom of 0...1 for real
        // audio: ambient ~0.003, speech ~0.05, loud ~0.15) onto a perceptual
        // 0...1 display range via dB, so meters and waveforms actually fill.
        static func displayLevel(rms: Float) -> Float {
            guard rms > 1e-5 else { return 0 }
            let db = 20 * log10(rms)
            let minDb: Float = -50, maxDb: Float = -12
            let norm = (db - minDb) / (maxDb - minDb)
            return min(max(norm, 0), 1)
        }
    }
}

// Lock-protected buffer written from the audio thread, read from the main actor.
private final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [Int16] = []
    private var smoothed: Float = 0
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var maxSamples = Int.max

    func configure(converter: AVAudioConverter, targetFormat: AVAudioFormat, maxSamples: Int) {
        lock.lock(); defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
        smoothed = 0
        self.converter = converter
        self.targetFormat = targetFormat
        self.maxSamples = maxSamples
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: false)
        smoothed = 0
    }

    var level: Float { lock.lock(); defer { lock.unlock() }; return smoothed }
    var count: Int { lock.lock(); defer { lock.unlock() }; return buffer.count }
    func samples() -> [Int16] { lock.lock(); defer { lock.unlock() }; return buffer }

    func process(_ input: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }
        let inputRate = input.format.sampleRate
        guard inputRate > 0 else { return }
        let ratio = targetFormat.sampleRate / inputRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 16
        guard capacity > 0,
              let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        _ = converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, let channel = out.int16ChannelData else { return }
        let n = Int(out.frameLength)
        guard n > 0 else { return }
        let ptr = channel[0]

        var sumSquares: Double = 0
        for i in 0..<n {
            let v = Double(ptr[i])
            sumSquares += v * v
        }
        let rms = Float(sqrt(sumSquares / Double(n)) / 32768.0)

        lock.lock()
        if buffer.count < maxSamples {
            let room = maxSamples - buffer.count
            let take = min(n, room)
            buffer.append(contentsOf: UnsafeBufferPointer(start: ptr, count: take))
        }
        smoothed = smoothed * 0.8 + min(max(rms, 0), 1) * 0.2
        lock.unlock()
    }
}
