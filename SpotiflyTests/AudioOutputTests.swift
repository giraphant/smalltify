//
//  AudioOutputTests.swift
//  SpotiflyTests
//
//  The stream header the audio output serves
//

import AVFoundation
import Foundation
@testable import Spotifly
import Testing

/// The CAF header `PCMStream` serves ahead of the PCM: what AVPlayer parses to play the stream.
/// Big-endian throughout, 68 bytes, as Apple's CAF specification lays the chunks out.
struct PCMStreamHeaderTests {
    private func bigEndian<T: FixedWidthInteger>(_: T.Type, at offset: Int, in data: Data) -> T {
        data[offset ..< offset + MemoryLayout<T>.size].reduce(T(0)) { $0 << 8 | T($1) }
    }

    @Test func `the header describes interleaved 16-bit stereo at 44.1 kHz`() {
        let header = PCMStream.cafHeader(dataBytes: 8000)

        #expect(header.count == 68)
        #expect(String(decoding: header[0 ..< 4], as: UTF8.self) == "caff")
        #expect(String(decoding: header[8 ..< 12], as: UTF8.self) == "desc")
        #expect(bigEndian(Int64.self, at: 12, in: header) == 32)
        #expect(Double(bitPattern: bigEndian(UInt64.self, at: 20, in: header)) == 44100)
        #expect(String(decoding: header[28 ..< 32], as: UTF8.self) == "lpcm")
        #expect(bigEndian(UInt32.self, at: 32, in: header) == 2) // little-endian integer samples
        #expect(bigEndian(UInt32.self, at: 36, in: header) == 4) // bytes per frame
        #expect(bigEndian(UInt32.self, at: 44, in: header) == 2) // channels
        #expect(bigEndian(UInt32.self, at: 48, in: header) == 16) // bits per channel
        #expect(String(decoding: header[52 ..< 56], as: UTF8.self) == "data")
        #expect(bigEndian(Int64.self, at: 56, in: header) == 8004) // the edit count is in the chunk
    }

    /// The header and the converted samples as a file Core Audio reads: the samples come back as
    /// they went in, to 16 bits, and out-of-range ones at full scale.
    @Test func `core audio reads the stream's samples back`() throws {
        let floats: [Float] = [0, 0.5, -0.5, 1, -1, 1.5, -1.5, 0.25]
        let pcm = AudioOutput.int16(floats.withUnsafeBufferPointer { Data(buffer: $0) })
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try (PCMStream.cafHeader(dataBytes: Int64(pcm.count)) + pcm).write(to: url)

        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: true)
        #expect(file.fileFormat.sampleRate == 44100)
        #expect(file.fileFormat.channelCount == 2)
        #expect(file.length == 4)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4))
        try file.read(into: buffer)
        let read = try Array(UnsafeBufferPointer(start: #require(buffer.floatChannelData?[0]), count: floats.count))
        for (got, sent) in zip(read, floats) {
            #expect(abs(got - max(-1, min(1, sent))) < 1.0 / 16384)
        }
    }
}
