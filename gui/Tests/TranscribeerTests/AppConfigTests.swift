import Foundation
import Testing
@testable import TranscribeerApp

struct AppConfigTests {

    @Test("Default config has expected values")
    func defaults() {
        let cfg = AppConfig()
        #expect(cfg.language == "auto")
        #expect(cfg.whisperModel == "large-v3-turbo")
        #expect(cfg.diarization == "pyannote")
        #expect(cfg.numSpeakers == 0)
        #expect(cfg.llmBackend == "ollama")
        #expect(cfg.llmModel == "llama3")
        #expect(cfg.ollamaHost == "http://localhost:11434")
        #expect(cfg.sessionsDir == "~/.transcribeer/sessions")
        #expect(cfg.pipelineMode == "record+transcribe+summarize")
        #expect(cfg.zoomAutoRecord == false)
        #expect(cfg.promptOnStop == true)
    }

    @Test("expandedSessionsDir resolves tilde to home directory")
    func expandedSessionsDir() {
        var cfg = AppConfig()
        cfg.sessionsDir = "~/custom/sessions"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(cfg.expandedSessionsDir == "\(home)/custom/sessions")
    }

    @Test("expandedSessionsDir passes through absolute paths unchanged")
    func absoluteSessionsDir() {
        var cfg = AppConfig()
        cfg.sessionsDir = "/tmp/sessions"
        #expect(cfg.expandedSessionsDir == "/tmp/sessions")
    }

    @Test("expandedCaptureBin resolves tilde")
    func expandedCaptureBin() {
        var cfg = AppConfig()
        cfg.captureBin = "~/.transcribeer/bin/capture-bin"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(cfg.expandedCaptureBin == "\(home)/.transcribeer/bin/capture-bin")
    }

    @Test("Equatable conformance compares all fields")
    func equatable() {
        let a = AppConfig()
        var b = AppConfig()
        #expect(a == b)

        b.language = "en"
        #expect(a != b)
    }
}
