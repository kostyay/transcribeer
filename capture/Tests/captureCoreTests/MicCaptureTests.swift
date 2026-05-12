import AVFoundation
import Testing
@testable @_spi(Testing) import CaptureCore

struct MicCaptureTests {
    @Test("Tap installation lets AVAudioEngine choose the native node format")
    func tapFormatUsesNativeNodeFormat() throws {
        let nodeFormat = try #require(AVAudioFormat(
            standardFormatWithSampleRate: 44_100,
            channels: 1
        ))

        #expect(MicCapture.tapFormatForInstallation(nodeFormat: nodeFormat) == nil)
    }

    @Test("Tap format logging describes native format selection")
    func tapFormatDescriptionUsesNodeFormat() throws {
        let nodeFormat = try #require(AVAudioFormat(
            standardFormatWithSampleRate: 44_100,
            channels: 1
        ))

        let description = MicCapture.tapFormatDescription(nodeFormat: nodeFormat, tapFormat: nil)

        #expect(description == "tapFormat: native sr=44100.0 ch=1")
    }
}
