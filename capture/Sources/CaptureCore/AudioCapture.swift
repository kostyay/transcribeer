import AVFoundation
import ScreenCaptureKit

public class AudioCapture: NSObject {
    public static let shared = AudioCapture()
    public override init() {}

    private var stream: SCStream?
    private var writer: WAVWriter?

    // Fix #2: thread-safe accepting flag
    private let acceptingLock = NSLock()
    private var _accepting = true
    private var accepting: Bool {
        get { acceptingLock.withLock { _accepting } }
        set { acceptingLock.withLock { _accepting = newValue } }
    }

    // Fixed formats per spec
    private let srcFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
    private let dstFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    // Fix #3: optional converter, initialized safely in start()
    private var converter: AVAudioConverter?

    public func start(writer: WAVWriter) async throws {
        self.writer = writer
        self.accepting = true

        // Fix #3: safe converter init with proper error
        guard let conv = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            throw CaptureError.converterFailed("Cannot create AVAudioConverter for 48kHz stereo → 16kHz mono")
        }
        converter = conv

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(
            display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = false
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let s = SCStream(filter: filter, configuration: config, delegate: nil)
        try s.addStreamOutput(
            self, type: .audio,
            sampleHandlerQueue: DispatchQueue(label: "audio.capture"))
        try await s.startCapture()
        self.stream = s
    }

    // Call from signal handler — safe to call from any thread
    public func stopAccepting() {
        accepting = false
    }

    /// Stop capture. Safe to call from any thread (e.g. signal handler).
    public func stop() {
        stopAccepting()
        let s = stream
        stream = nil
        Task { try? await s?.stopCapture() }
    }
}

public enum CaptureError: Error {
    case noDisplay
    case converterFailed(String)
}

extension AudioCapture: SCStreamOutput {
    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio, accepting else { return }

        // Build source AVAudioPCMBuffer from CMSampleBuffer
        let numFrames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numFrames > 0 else { return }

        // Fix #1: allocate properly-sized ABL for stereo (2 AudioBuffer entries)
        let ablSize = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size
        let ablPtr = UnsafeMutableRawPointer.allocate(byteCount: ablSize, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { ablPtr.deallocate() }
        let abl = ablPtr.bindMemory(to: AudioBufferList.self, capacity: 1)
        abl.pointee.mNumberBuffers = 0

        var blockRef: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: abl,
            bufferListSize: ablSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockRef)
        guard status == noErr else { return }

        // Copy channel data into AVAudioPCMBuffer
        guard let srcBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: AVAudioFrameCount(numFrames)) else { return }
        srcBuf.frameLength = AVAudioFrameCount(numFrames)

        withUnsafeMutablePointer(to: &abl.pointee.mBuffers) { start in
            let ablBuffers = UnsafeBufferPointer<AudioBuffer>(
                start: start,
                count: Int(abl.pointee.mNumberBuffers))
            for (i, buf) in ablBuffers.enumerated() {
                guard i < Int(srcFormat.channelCount), let srcData = buf.mData,
                      let dstData = srcBuf.floatChannelData?[i] else { continue }
                memcpy(dstData, srcData, Int(buf.mDataByteSize))
            }
        }

        // Convert 48kHz stereo → 16kHz mono
        let ratio = dstFormat.sampleRate / srcFormat.sampleRate
        let outFrames = AVAudioFrameCount(Double(numFrames) * ratio) + 1
        guard let dstBuf = AVAudioPCMBuffer(
            pcmFormat: dstFormat, frameCapacity: outFrames) else { return }

        // Fix #3: guard optional converter
        guard let converter = converter else { return }
        var convError: NSError?
        converter.convert(to: dstBuf, error: &convError) { _, outStatus in
            outStatus.pointee = .haveData
            return srcBuf
        }
        guard convError == nil, dstBuf.frameLength > 0 else { return }

        // Float32 → Int16, clamped per-sample
        let floats = dstBuf.floatChannelData![0]
        let count = Int(dstBuf.frameLength)
        var int16s = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let clamped = max(-1.0, min(1.0, floats[i]))
            int16s[i] = Int16(clamped * 32767)
        }

        writer?.append(int16s)
    }
}
