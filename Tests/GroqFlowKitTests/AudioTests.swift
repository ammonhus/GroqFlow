import XCTest
@testable import GroqFlowKit

final class AudioTests: XCTestCase {

    // MARK: - little-endian readers

    private func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }
    private func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }
    private func tag(_ b: [UInt8], _ o: Int) -> String {
        String(bytes: b[o..<o + 4], encoding: .ascii) ?? ""
    }

    // MARK: - WAV header

    func testWavHeaderKnownSamples() {
        let samples: [Int16] = [0, 1, -1, 32767, -32768, 100, -100]
        let bytes = [UInt8](WAVEncoder.wavData(fromPCM16: samples, sampleRate: 16000))

        XCTAssertEqual(bytes.count, 44 + samples.count * 2)

        XCTAssertEqual(tag(bytes, 0), "RIFF")
        XCTAssertEqual(u32(bytes, 4), UInt32(36 + samples.count * 2))   // ChunkSize
        XCTAssertEqual(tag(bytes, 8), "WAVE")

        XCTAssertEqual(tag(bytes, 12), "fmt ")
        XCTAssertEqual(u32(bytes, 16), 16)          // Subchunk1Size (PCM)
        XCTAssertEqual(u16(bytes, 20), 1)           // AudioFormat (PCM)
        XCTAssertEqual(u16(bytes, 22), 1)           // NumChannels
        XCTAssertEqual(u32(bytes, 24), 16000)       // SampleRate
        XCTAssertEqual(u32(bytes, 28), 32000)       // ByteRate = 16000 * 1 * 2
        XCTAssertEqual(u16(bytes, 32), 2)           // BlockAlign
        XCTAssertEqual(u16(bytes, 34), 16)          // BitsPerSample

        XCTAssertEqual(tag(bytes, 36), "data")
        XCTAssertEqual(u32(bytes, 40), UInt32(samples.count * 2))   // Subchunk2Size
    }

    func testWavSamplePayloadLittleEndian() {
        let samples: [Int16] = [0, 1, -1, 32767, -32768, 12345, -12345]
        let bytes = [UInt8](WAVEncoder.wavData(fromPCM16: samples, sampleRate: 16000))

        for (i, s) in samples.enumerated() {
            let raw = u16(bytes, 44 + i * 2)
            XCTAssertEqual(Int16(bitPattern: raw), s, "sample \(i) mismatch")
        }
    }

    func testEmptySamplesHeader() {
        let bytes = [UInt8](WAVEncoder.wavData(fromPCM16: [], sampleRate: 16000))

        XCTAssertEqual(bytes.count, 44)             // header only
        XCTAssertEqual(tag(bytes, 0), "RIFF")
        XCTAssertEqual(u32(bytes, 4), 36)           // ChunkSize = 36 + 0
        XCTAssertEqual(tag(bytes, 8), "WAVE")
        XCTAssertEqual(tag(bytes, 36), "data")
        XCTAssertEqual(u32(bytes, 40), 0)           // no sample bytes
    }

    func testSampleRateFieldsHonorArgument() {
        let bytes = [UInt8](WAVEncoder.wavData(fromPCM16: [1, 2, 3], sampleRate: 8000))
        XCTAssertEqual(u32(bytes, 24), 8000)        // SampleRate
        XCTAssertEqual(u32(bytes, 28), 16000)       // ByteRate = 8000 * 2
        XCTAssertEqual(u16(bytes, 32), 2)           // BlockAlign unchanged
    }

    // MARK: - duration math

    func testDurationMath() {
        typealias M = AudioRecorder.AudioMath
        XCTAssertEqual(M.duration(sampleCount: 16000, sampleRate: 16000), 1.0, accuracy: 1e-9)
        XCTAssertEqual(M.duration(sampleCount: 8000, sampleRate: 16000), 0.5, accuracy: 1e-9)
        XCTAssertEqual(M.duration(sampleCount: 6400, sampleRate: 16000), 0.4, accuracy: 1e-9)
        XCTAssertEqual(M.duration(sampleCount: 0, sampleRate: 16000), 0.0, accuracy: 1e-9)
        XCTAssertEqual(M.duration(sampleCount: 1000, sampleRate: 0), 0.0)   // guarded divide
    }

    func testMinDurationThreshold() {
        typealias M = AudioRecorder.AudioMath
        // 0.4 s at 16 kHz is exactly 6400 samples; the boundary keeps, one under discards.
        XCTAssertGreaterThanOrEqual(M.duration(sampleCount: 6400, sampleRate: 16000), M.minDuration)
        XCTAssertLessThan(M.duration(sampleCount: 6399, sampleRate: 16000), M.minDuration)
    }
}

@MainActor
final class AudioRecorderInitTests: XCTestCase {
    // Regression: AVAudioEngine.prepare() on an unconnected graph throws an
    // NSException that AppKit swallows at launch, silently killing startup.
    func testInitDoesNotRaise() {
        _ = AudioRecorder()
    }
}
