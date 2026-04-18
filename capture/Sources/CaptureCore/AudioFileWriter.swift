import AVFoundation

public enum AudioFileError: Error {
    case cannotOpen(String)
}

/// Writes audio samples to a compressed M4A/AAC file via AVAudioFile.
///
/// Thread-safe: `append(_:)` and `close()` can be called from any thread.
public final class AudioFileWriter {
    public static let shared = AudioFileWriter()
    public init() {}

    private let lock = NSLock()
    private var audioFile: AVAudioFile?

    /// Open a new audio file for writing.
    ///
    /// - Parameters:
    ///   - url: Destination URL (should have `.m4a` extension).
    ///   - sampleRate: Output sample rate in Hz (default: 16000).
    ///   - channels: Number of channels (default: 1 for mono).
    public func open(
        url: URL,
        sampleRate: Double = 16000,
        channels: Int = 1
    ) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
        ]
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: settings)
        } catch {
            throw AudioFileError.cannotOpen(url.path)
        }
    }

    /// Append PCM audio samples to the file.
    ///
    /// The buffer's format must be compatible with the file's processing format
    /// (Float32, matching sample rate and channel count).
    public func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard let file = audioFile, buffer.frameLength > 0 else { return }
            try? file.write(from: buffer)
        }
    }

    /// Close the file. Safe to call multiple times.
    public func close() {
        lock.withLock {
            audioFile = nil
        }
    }
}
