import AVFoundation
import Foundation

/// Cheaply detect whether a recording contains any audible signal.
///
/// Used up-front in the transcribe pipeline to avoid spending several minutes
/// of WhisperKit CPU on a well-formed WAV of zero-valued samples — the common
/// failure mode when ScreenCaptureKit records with no audio playing through
/// the system speakers, or when the mic is muted mid-session.
public enum AudioValidation {
    /// Peak amplitude below this value (≈ -60 dBFS) is treated as silent. Sits
    /// just above digital dither / noise floor; permissive enough to accept
    /// whispered (~-50 dBFS) and distant-mic (~-40 dBFS) recordings.
    public static let defaultPeakThreshold: Float = 0.001

    /// Size of each scan window. 30 s keeps memory bounded while still
    /// detecting delayed audio without materializing multi-hour recordings.
    public static let defaultProbeSeconds: Double = 30.0

    /// Returns `true` iff any scanned window reaches a peak absolute
    /// amplitude of at least `peakThreshold`.
    ///
    /// Conservative fallback: any I/O or allocation failure returns `true` so
    /// the real decoder downstream can surface the actual format/permission
    /// error instead of having this guard masquerade as a silent-audio
    /// problem.
    public static func hasAudibleSignal(
        at url: URL,
        peakThreshold: Float = defaultPeakThreshold,
        probeSeconds: Double = defaultProbeSeconds
    ) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else {
            return true
        }

        let sampleRate = file.processingFormat.sampleRate
        let requestedFrames = Int64(probeSeconds * sampleRate)
        let framesPerWindow = AVAudioFrameCount(min(max(requestedFrames, 1), file.length))
        guard framesPerWindow > 0 else { return false }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: framesPerWindow
        ) else {
            return true
        }

        while file.framePosition < file.length {
            buffer.frameLength = 0
            let remaining = file.length - file.framePosition
            let framesToRead = AVAudioFrameCount(min(Int64(framesPerWindow), remaining))
            do {
                try file.read(into: buffer, frameCount: framesToRead)
            } catch {
                return true
            }
            guard buffer.frameLength > 0 else { break }
            if bufferHasAudiblePeak(buffer, peakThreshold: peakThreshold) { return true }
        }
        return false
    }

    private static func bufferHasAudiblePeak(
        _ buffer: AVAudioPCMBuffer,
        peakThreshold: Float
    ) -> Bool {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
            return false
        }

        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        for channelIndex in 0..<channelCount {
            let samples = channels[channelIndex]
            for frameIndex in 0..<frames where abs(samples[frameIndex]) >= peakThreshold {
                return true
            }
        }
        return false
    }

    /// Throws `AudioValidationError.silent` if `hasAudibleSignal` returns
    /// `false`. Convenience wrapper for pipeline callers that want to abort
    /// before loading WhisperKit. Keeps the probe-window reported in the
    /// error message in lock-step with the window actually probed.
    public static func ensureAudibleSignal(
        at url: URL,
        peakThreshold: Float = defaultPeakThreshold,
        probeSeconds: Double = defaultProbeSeconds
    ) throws {
        guard hasAudibleSignal(
            at: url,
            peakThreshold: peakThreshold,
            probeSeconds: probeSeconds
        ) else {
            throw AudioValidationError.silent(url: url, probeSeconds: probeSeconds)
        }
    }
}

/// Surface-level error type for pipeline callers that abort on a failed
/// audible-signal check.
public enum AudioValidationError: LocalizedError {
    case silent(url: URL, probeSeconds: Double)

    public var errorDescription: String? {
        switch self {
        case let .silent(url, probeSeconds):
            let seconds = Int(probeSeconds.rounded())
            return """
                Recording appears silent (no audible signal found while scanning \
                \(seconds) seconds at a time in \(url.lastPathComponent)). Common causes:
                  • System-audio capture with nothing playing through speakers.
                  • System Audio Recording permission revoked mid-session.
                  • Microphone input muted or wrong device selected.
                Play the file in a media player to confirm, then re-record.
                """
        }
    }
}
