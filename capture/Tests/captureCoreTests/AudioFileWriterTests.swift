import AVFoundation
import Foundation
import Testing
@preconcurrency @testable import CaptureCore

// MARK: - Helpers

private func makeTempURL(ext: String = "m4a") -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("audiotest_\(UUID().uuidString).\(ext)")
}

/// Create a PCM buffer with the given Float32 samples at 16kHz mono.
private func pcmBuffer(samples: [Float]) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    let channelData = buffer.floatChannelData![0]
    for (i, s) in samples.enumerated() {
        channelData[i] = s
    }
    return buffer
}

/// Read back all samples from an audio file as Float32.
private func readSamples(at url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: file.fileFormat.sampleRate,
        channels: 1,
        interleaved: false
    )!
    let frameCount = AVAudioFrameCount(file.length)
    guard frameCount > 0 else { return [] }
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    try file.read(into: buffer)
    let ptr = buffer.floatChannelData![0]
    return Array(UnsafeBufferPointer(start: ptr, count: Int(buffer.frameLength)))
}

/// Verify two sample arrays are approximately equal (AAC is lossy).
private func verifySamplesApproxEqual(
    _ actual: [Float],
    _ expected: [Float],
    tolerance: Float = 0.15,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    // AAC encoding may add padding frames; compare the overlapping prefix
    #expect(!actual.isEmpty && !expected.isEmpty, "Both arrays must have samples", sourceLocation: sourceLocation)

    let maxDiff = zip(actual, expected)
        .map { abs($0 - $1) }
        .max() ?? 0
    #expect(
        maxDiff < tolerance,
        "Max sample difference \(maxDiff) exceeds tolerance \(tolerance)",
        sourceLocation: sourceLocation
    )
}

// MARK: - Tests

struct AudioFileWriterTests {
    @Test("Written samples can be read back with acceptable lossy accuracy")
    func writeAndReadBack() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let samples: [Float] = (0..<1600).map { Float(sin(Double($0) * 0.1)) * 0.8 }

        let writer = AudioFileWriter()
        try writer.open(url: url)
        writer.append(pcmBuffer(samples: samples))
        writer.close()

        let readBack = try readSamples(at: url)
        verifySamplesApproxEqual(readBack, samples)
    }

    @Test("Empty file is valid (no samples written)")
    func emptyFile() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = AudioFileWriter()
        try writer.open(url: url)
        writer.close()

        #expect(FileManager.default.fileExists(atPath: url.path))
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0
        // M4A container has some overhead even with no audio
        #expect(size > 0, "File should exist with container metadata")
    }

    @Test("Multiple appends accumulate all samples")
    func multipleAppends() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let chunk1: [Float] = (0..<800).map { Float(sin(Double($0) * 0.1)) * 0.5 }
        let chunk2: [Float] = (0..<800).map { Float(cos(Double($0) * 0.1)) * 0.5 }

        let writer = AudioFileWriter()
        try writer.open(url: url)
        writer.append(pcmBuffer(samples: chunk1))
        writer.append(pcmBuffer(samples: chunk2))
        writer.close()

        let readBack = try readSamples(at: url)
        let combined = chunk1 + chunk2
        verifySamplesApproxEqual(readBack, combined)
    }

    @Test("Appending an empty buffer does not corrupt the file")
    func appendEmptyBuffer() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let samples: [Float] = [0.5, -0.5, 0.25, -0.25]

        let writer = AudioFileWriter()
        try writer.open(url: url)
        writer.append(pcmBuffer(samples: []))
        writer.append(pcmBuffer(samples: samples))
        writer.append(pcmBuffer(samples: []))
        writer.close()

        let readBack = try readSamples(at: url)
        #expect(readBack.count >= samples.count, "Should contain at least the written samples")
    }

    @Test("Opening invalid path throws AudioFileError.cannotOpen")
    func invalidPathThrows() {
        #expect(throws: AudioFileError.self) {
            let writer = AudioFileWriter()
            try writer.open(url: URL(fileURLWithPath: "/nonexistent/dir/file.m4a"))
        }
    }

    @Test("Close is idempotent — calling twice does not crash")
    func doubleClose() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = AudioFileWriter()
        try writer.open(url: url)
        writer.append(pcmBuffer(samples: [0.1, 0.2, 0.3]))
        writer.close()
        writer.close()

        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("File size is significantly smaller than equivalent raw PCM",
          .tags(.performance))
    func compressionRatio() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        // 1 second of 16kHz mono audio = 16000 samples = 64KB raw PCM (Float32)
        let oneSecond: [Float] = (0..<16000).map { Float(sin(Double($0) * 0.3)) * 0.7 }

        let writer = AudioFileWriter()
        try writer.open(url: url)
        writer.append(pcmBuffer(samples: oneSecond))
        writer.close()

        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0
        let rawSize: UInt64 = 16000 * 4  // Float32 = 4 bytes/sample
        #expect(
            fileSize < rawSize / 2,
            "AAC file (\(fileSize) bytes) should be at least 2× smaller than raw PCM (\(rawSize) bytes)"
        )
    }

    @Test("Concurrent appends produce valid file without corruption")
    func concurrentAppends() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = AudioFileWriter()
        try writer.open(url: url)

        let iterations = 50
        let samplesPerIteration = 320  // 20ms at 16kHz
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let samples = (0..<samplesPerIteration).map {
                Float(sin(Double($0 + i * samplesPerIteration) * 0.05)) * 0.6
            }
            writer.append(pcmBuffer(samples: samples))
        }
        writer.close()

        // Verify the file can be read without error
        let readBack = try readSamples(at: url)
        #expect(readBack.count > 0, "Should contain audio data after concurrent writes")
    }
}

// MARK: - Tags

extension Tag {
    @Tag static var performance: Self
}
