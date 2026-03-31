import XCTest
@testable import CaptureCore

final class WAVWriterTests: XCTestCase {

    func makeTempPath() -> String {
        NSTemporaryDirectory() + "wavtest_\(UUID().uuidString).wav"
    }

    // Verify header bytes and size fields after writing 2 known samples
    func testHeaderAndSamples() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let writer = WAVWriter()
        try writer.open(path: path)
        writer.append([100, -100])  // 4 bytes of audio data
        writer.close()

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(data.count, 48, "44-byte header + 4 bytes of audio")

        // "RIFF"
        XCTAssertEqual(data[0..<4], Data([0x52, 0x49, 0x46, 0x46]))
        // ChunkSize = 36 + 4 = 40
        XCTAssertEqual(le32(data, offset: 4), 40)
        // "WAVE"
        XCTAssertEqual(data[8..<12], Data([0x57, 0x41, 0x56, 0x45]))
        // "fmt "
        XCTAssertEqual(data[12..<16], Data([0x66, 0x6d, 0x74, 0x20]))
        // Subchunk1Size = 16
        XCTAssertEqual(le32(data, offset: 16), 16)
        // AudioFormat = 1 (PCM)
        XCTAssertEqual(le16(data, offset: 20), 1)
        // NumChannels = 1
        XCTAssertEqual(le16(data, offset: 22), 1)
        // SampleRate = 16000
        XCTAssertEqual(le32(data, offset: 24), 16000)
        // ByteRate = 32000
        XCTAssertEqual(le32(data, offset: 28), 32000)
        // BlockAlign = 2
        XCTAssertEqual(le16(data, offset: 32), 2)
        // BitsPerSample = 16
        XCTAssertEqual(le16(data, offset: 34), 16)
        // "data"
        XCTAssertEqual(data[36..<40], Data([0x64, 0x61, 0x74, 0x61]))
        // Subchunk2Size = 4
        XCTAssertEqual(le32(data, offset: 40), 4)

        // Sample values
        XCTAssertEqual(leInt16(data, offset: 44), 100)
        XCTAssertEqual(leInt16(data, offset: 46), -100)
    }

    // Verify header is valid with zero audio samples
    func testEmptyFile() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let writer = WAVWriter()
        try writer.open(path: path)
        writer.close()

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(data.count, 44)
        XCTAssertEqual(le32(data, offset: 4), 36)   // ChunkSize
        XCTAssertEqual(le32(data, offset: 40), 0)   // Subchunk2Size
    }

    // Verify Int16.max/min write correctly (boundary values)
    func testBoundaryValues() throws {
        let path = makeTempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let writer = WAVWriter()
        try writer.open(path: path)
        writer.append([Int16.max, Int16.min])
        writer.close()

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        XCTAssertEqual(leInt16(data, offset: 44), Int16.max)
        XCTAssertEqual(leInt16(data, offset: 46), Int16.min)
    }

    // MARK: - Helpers
    private func le32(_ data: Data, offset: Int) -> UInt32 {
        data[offset..<(offset+4)].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }
    private func le16(_ data: Data, offset: Int) -> UInt16 {
        data[offset..<(offset+2)].withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
    }
    private func leInt16(_ data: Data, offset: Int) -> Int16 {
        data[offset..<(offset+2)].withUnsafeBytes { $0.load(as: Int16.self).littleEndian }
    }
}
