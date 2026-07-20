import XCTest
@testable import GroqFlowKit

final class LevelDisplayTests: XCTestCase {
    // Raw RMS from AudioSink lives in the bottom of the 0...1 range: quiet-room
    // ambient ~0.0026, normal speech ~0.05, loud ~0.15. displayLevel maps that
    // to a perceptual 0...1 so the meter/waveform actually fill.
    func testAmbientIsNearZero() {
        XCTAssertLessThan(AudioRecorder.AudioMath.displayLevel(rms: 0.0026), 0.05)
    }
    func testDigitalSilenceIsZero() {
        XCTAssertEqual(AudioRecorder.AudioMath.displayLevel(rms: 0), 0, accuracy: 0.0001)
    }
    func testNormalSpeechFillsAboutHalf() {
        let v = AudioRecorder.AudioMath.displayLevel(rms: 0.05)
        XCTAssertGreaterThan(v, 0.45)
        XCTAssertLessThan(v, 0.8)
    }
    func testLoudSpeechNearFull() {
        XCTAssertGreaterThan(AudioRecorder.AudioMath.displayLevel(rms: 0.15), 0.8)
    }
    func testClampedToOne() {
        XCTAssertLessThanOrEqual(AudioRecorder.AudioMath.displayLevel(rms: 0.9), 1.0)
    }
}
