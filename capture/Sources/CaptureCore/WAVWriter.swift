import Foundation

public enum WAVError: Error {
    case cannotOpen(String)
}

public class WAVWriter {
    public static let shared = WAVWriter()
    public init() {}

    private let lock = NSLock()
    private var fileHandle: FileHandle?
    private var bytesWritten: UInt32 = 0

    public func open(path: String) throws {
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let fh = FileHandle(forWritingAtPath: path) else {
            throw WAVError.cannotOpen(path)
        }
        fileHandle = fh
        bytesWritten = 0
        fh.write(makeHeader(dataBytes: 0))
    }

    public func append(_ samples: [Int16]) {
        lock.withLock {
            guard let fh = fileHandle, !samples.isEmpty else { return }
            var data = Data(capacity: samples.count * 2)
            for s in samples {
                var le = s.littleEndian
                withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
            }
            fh.write(data)
            bytesWritten += UInt32(samples.count * 2)
        }
    }

    public func close() {
        lock.withLock {
            guard let fh = fileHandle else { return }
            defer {
                fh.closeFile()
                fileHandle = nil
            }
            // Patch ChunkSize at offset 4
            fh.seek(toFileOffset: 4)
            var v = (36 + bytesWritten).littleEndian
            fh.write(Data(bytes: &v, count: 4))
            // Patch Subchunk2Size at offset 40
            fh.seek(toFileOffset: 40)
            v = bytesWritten.littleEndian
            fh.write(Data(bytes: &v, count: 4))
        }
    }

    // MARK: - Private

    private func makeHeader(dataBytes: UInt32) -> Data {
        var h = Data(count: 44)
        func w32(_ offset: Int, _ value: UInt32) {
            var v = value.littleEndian
            h.replaceSubrange(offset..<(offset+4), with: withUnsafeBytes(of: &v) { Array($0) })
        }
        func w16(_ offset: Int, _ value: UInt16) {
            var v = value.littleEndian
            h.replaceSubrange(offset..<(offset+2), with: withUnsafeBytes(of: &v) { Array($0) })
        }
        h.replaceSubrange(0..<4,  with: [0x52, 0x49, 0x46, 0x46]) // RIFF
        w32(4,  36 + dataBytes)                                    // ChunkSize (placeholder)
        h.replaceSubrange(8..<12, with: [0x57, 0x41, 0x56, 0x45]) // WAVE
        h.replaceSubrange(12..<16,with: [0x66, 0x6d, 0x74, 0x20]) // fmt
        w32(16, 16)                                                // Subchunk1Size
        w16(20, 1)                                                 // AudioFormat PCM
        w16(22, 1)                                                 // NumChannels
        w32(24, 16000)                                             // SampleRate
        w32(28, 32000)                                             // ByteRate
        w16(32, 2)                                                 // BlockAlign
        w16(34, 16)                                                // BitsPerSample
        h.replaceSubrange(36..<40,with: [0x64, 0x61, 0x74, 0x61]) // data
        w32(40, dataBytes)                                         // Subchunk2Size (placeholder)
        return h
    }
}
