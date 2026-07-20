import Foundation

// Builds a canonical 44-byte-header PCM WAV in memory from 16-bit mono samples.
public enum WAVEncoder {
    public static func wavData(fromPCM16 samples: [Int16], sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize: UInt32 = UInt32(samples.count) * UInt32(bitsPerSample / 8)
        let chunkSize: UInt32 = 36 + dataSize

        var data = Data(capacity: 44 + samples.count * 2)

        // RIFF header
        data.append(contentsOf: Array("RIFF".utf8))
        data.appendLE(chunkSize)
        data.append(contentsOf: Array("WAVE".utf8))

        // fmt subchunk
        data.append(contentsOf: Array("fmt ".utf8))
        data.appendLE(UInt32(16))          // Subchunk1Size for PCM
        data.appendLE(UInt16(1))           // AudioFormat = PCM
        data.appendLE(numChannels)
        data.appendLE(UInt32(sampleRate))
        data.appendLE(byteRate)
        data.appendLE(blockAlign)
        data.appendLE(bitsPerSample)

        // data subchunk
        data.append(contentsOf: Array("data".utf8))
        data.appendLE(dataSize)

        // sample payload, little-endian
        if !samples.isEmpty {
            var le = [Int16](repeating: 0, count: samples.count)
            for i in samples.indices { le[i] = samples[i].littleEndian }
            le.withUnsafeBytes { data.append(contentsOf: $0) }
        }

        return data
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    mutating func appendLE(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
