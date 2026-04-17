import Foundation
import os.log

private let logger = Logger(subsystem: "com.transcribeer", category: "pipeline")

/// Appends timestamped lines to a session's `run.log` file.
private struct SessionLogger {
    let logPath: URL

    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .none,
            timeStyle: .medium
        )
        let data = Data("[\(timestamp)] \(message)\n".utf8)

        if let handle = try? FileHandle(forWritingTo: logPath) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logPath)
        }
    }
}

/// Runs the transcribeer pipeline using native Swift services.
@Observable
@MainActor
final class PipelineRunner {
    var state: AppState = .idle
    var currentSession: URL?
    var promptProfile: String?

    /// True when the current recording was auto-started by Zoom detection.
    var zoomAutoStarted = false

    /// Which session is actively being transcribed right now, if any.
    /// Set for both new recordings and re-transcribe-from-history flows so
    /// the detail view can decide whether to render the live preview.
    var transcribingSession: URL?

    /// Transcription progress (0..1), driven by WhisperKit.
    var transcriptionProgress: Double? { transcriptionService.progress }

    let transcriptionService = TranscriptionService()

    private var captureProcess: Process?
    private var pipelineTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?

    func startRecording(config: AppConfig) {
        guard !state.isBusy else { return }

        let session = SessionManager.newSession(sessionsDir: config.expandedSessionsDir)
        currentSession = session
        promptProfile = nil
        state = .recording(startTime: Date())

        pipelineTask = Task {
            await runPipeline(session: session, config: config)
        }
    }

    func stopRecording() {
        guard state.isRecording else { return }
        if let captureProcess, captureProcess.isRunning {
            captureProcess.interrupt()  // SIGINT
        }
    }

    /// Cancel an in-flight transcription or summarization. Does nothing while
    /// recording (use `stopRecording` for that).
    func cancelProcessing() {
        switch state {
        case .transcribing, .summarizing:
            transcriptionService.cancel()
            processingTask?.cancel()
            pipelineTask?.cancel()
        default:
            break
        }
    }

    private func runPipeline(session: URL, config: AppConfig) async {
        let audioPath = session.appendingPathComponent("audio.m4a")
        let transcriptPath = session.appendingPathComponent("transcript.txt")
        let summaryPath = session.appendingPathComponent("summary.md")
        let logger = SessionLogger(logPath: session.appendingPathComponent("run.log"))

        logger.log("session=\(session.path)")
        logger.log("pipeline=\(config.pipelineMode) lang=\(config.language) diarize=\(config.diarization)")

        // 1. Record — use capture-bin directly
        logger.log("capture-bin=\(config.expandedCaptureBin)")
        guard await performRecording(config: config, audioPath: audioPath, logger: logger) else {
            return
        }

        if config.pipelineMode == "record-only" {
            finishSession(session)
            return
        }

        // 2. Transcribe (WhisperKit + SpeakerKit)
        guard await performTranscription(
            config: config,
            audioPath: audioPath,
            transcriptPath: transcriptPath,
            logger: logger
        ) else { return }

        if config.pipelineMode == "record+transcribe" {
            finishSession(session)
            return
        }

        // 3. Summarize (LLM) — failure here is non-fatal
        await performSummarization(
            config: config,
            transcriptPath: transcriptPath,
            summaryPath: summaryPath,
            logger: logger
        )

        finishSession(session)
    }

    private func performRecording(
        config: AppConfig,
        audioPath: URL,
        logger: SessionLogger
    ) async -> Bool {
        let result = await runCapture(
            captureBin: config.expandedCaptureBin,
            audioPath: audioPath
        )

        switch result {
        case let .error(err):
            logger.log("capture failed: \(err)")
            state = .error(err)
            NotificationManager.notifyError(err)
            return false
        case .noAudio:
            logger.log("no audio captured")
            state = .idle
            return false
        case .recorded:
            let size = (try? FileManager.default.attributesOfItem(
                atPath: audioPath.path,
            )[.size] as? Int) ?? 0
            logger.log("recorded \(size) bytes")
            return true
        }
    }

    private func performTranscription(
        config: AppConfig,
        audioPath: URL,
        transcriptPath: URL,
        logger: SessionLogger,
    ) async -> Bool {
        state = .transcribing
        transcribingSession = transcriptPath.deletingLastPathComponent()
        defer { transcribingSession = nil }
        logger.log("transcription started")
        do {
            let result = try await transcribeAndFormat(
                audioPath: audioPath,
                language: config.language,
                model: config.whisperModel,
                diarization: config.diarization,
                numSpeakers: config.numSpeakers,
            )
            try result.write(to: transcriptPath, atomically: true, encoding: .utf8)
            SessionManager.setLanguage(transcriptPath.deletingLastPathComponent(), config.language)
            logger.log("transcription done")
            return true
        } catch is CancellationError {
            logger.log("transcription cancelled")
            state = .idle
            return false
        } catch {
            let message = "Transcription failed: \(error.localizedDescription)"
            logger.log(message)
            state = .error(message)
            NotificationManager.notifyError(message)
            return false
        }
    }

    private func performSummarization(
        config: AppConfig,
        transcriptPath: URL,
        summaryPath: URL,
        logger: SessionLogger
    ) async {
        state = .summarizing
        logger.log("summarization started backend=\(config.llmBackend) model=\(config.llmModel) profile=\(promptProfile ?? "default")")
        do {
            let transcript = try String(contentsOf: transcriptPath, encoding: .utf8)
            let customPrompt = SummarizationService.loadPromptProfile(promptProfile)
            let summary = try await SummarizationService.summarize(
                transcript: transcript,
                backend: config.llmBackend,
                model: config.llmModel,
                ollamaHost: config.ollamaHost,
                prompt: customPrompt
            )
            try summary.write(to: summaryPath, atomically: true, encoding: .utf8)
            logger.log("summarization done")
        } catch {
            logger.log("summarization failed: \(error.localizedDescription)")
            // Non-fatal — transcript is what matters.
        }
    }

    private func finishSession(_ session: URL) {
        state = .done(sessionPath: session.path)
        NotificationManager.notifyDone(sessionName: SessionManager.displayName(session))
    }

    // MARK: - Transcription + Diarization + Formatting

    private func transcribeAndFormat(
        audioPath: URL,
        language: String,
        model: String,
        diarization: String,
        numSpeakers: Int,
    ) async throws -> String {
        // Ensure the configured model is loaded. Runs on the service's
        // MainActor but quickly hands off to a background task for the
        // expensive compile/prewarm steps WhisperKit performs internally.
        try await transcriptionService.loadModel(name: model)

        // Transcription and diarization are independent: both consume the
        // same audio file and produce disjoint segment streams. Run them in
        // parallel so the pipeline's wall time is dominated by the slower of
        // the two instead of their sum.
        async let whisperSegmentsTask = transcriptionService.transcribe(
            audioURL: audioPath,
            language: language,
        )

        async let diarSegmentsTask: [DiarSegment] = {
            guard diarization != "none" else { return [] }
            return try await DiarizationService.diarize(
                audioURL: audioPath,
                numSpeakers: numSpeakers > 0 ? numSpeakers : nil,
            )
        }()

        let whisperSegments = try await whisperSegmentsTask
        let diarSegments = try await diarSegmentsTask

        try Task.checkCancellation()

        let labeled = TranscriptFormatter.assignSpeakers(
            whisperSegments: whisperSegments,
            diarSegments: diarSegments,
        )
        return TranscriptFormatter.format(labeled)
    }

    // MARK: - Capture

    private enum CaptureResult {
        case recorded
        case noAudio
        case error(String)
    }

    private func runCapture(captureBin: String, audioPath: URL) async -> CaptureResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: captureBin)
                proc.arguments = [audioPath.path]
                let errPipe = Pipe()
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = errPipe

                do {
                    try proc.run()
                } catch {
                    continuation.resume(returning: .error(
                        "Failed to launch capture-bin: \(error.localizedDescription)"
                    ))
                    return
                }

                Task { @MainActor in
                    self?.captureProcess = proc
                }

                proc.waitUntilExit()

                Task { @MainActor in
                    self?.captureProcess = nil
                }

                let stderr = String(
                    data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

                if proc.terminationStatus != 0 {
                    if stderr.contains("Screen & System Audio Recording") {
                        continuation.resume(returning: .error(
                            "Grant Screen Recording in System Settings → Privacy"
                        ))
                    } else {
                        continuation.resume(returning: .error(
                            "capture-bin exited \(proc.terminationStatus)"
                        ))
                    }
                    return
                }

                let size = (try? FileManager.default.attributesOfItem(
                    atPath: audioPath.path
                )[.size] as? UInt64) ?? 0
                continuation.resume(returning: size > 0 ? .recorded : .noAudio)
            }
        }
    }

    // MARK: - History re-runs

    /// Result of a pipeline operation.
    struct CLIResult {
        let ok: Bool
        let error: String
    }

    /// Re-transcribe a session from its audio.
    ///
    /// `languageOverride` wins over `config.language` when non-nil. Used by the
    /// session detail view to run Hebrew on one recording while the global
    /// default stays on English (or auto).
    func transcribeSession(
        _ session: URL,
        config: AppConfig,
        languageOverride: String? = nil,
    ) async -> CLIResult {
        guard let audioPath = SessionManager.audioURL(in: session) else {
            return CLIResult(ok: false, error: "Audio file not found")
        }
        let txPath = session.appendingPathComponent("transcript.txt")
        let language = languageOverride ?? config.language

        logger.info("re-transcribe: \(audioPath.path) lang=\(language)")

        let previousState = state
        state = .transcribing
        transcribingSession = session
        defer {
            transcribingSession = nil
            if case .transcribing = state { state = previousState }
        }

        do {
            let result = try await transcribeAndFormat(
                audioPath: audioPath,
                language: language,
                model: config.whisperModel,
                diarization: config.diarization,
                numSpeakers: config.numSpeakers,
            )
            try result.write(to: txPath, atomically: true, encoding: .utf8)
            SessionManager.setLanguage(session, language)
            return CLIResult(ok: true, error: "")
        } catch is CancellationError {
            logger.info("re-transcribe cancelled")
            return CLIResult(ok: false, error: "Cancelled")
        } catch {
            logger.error("re-transcribe failed: \(error.localizedDescription)")
            return CLIResult(ok: false, error: error.localizedDescription)
        }
    }

    /// Re-summarize a session from its transcript.
    func summarizeSession(
        _ session: URL,
        config: AppConfig,
        profile: String?
    ) async -> CLIResult {
        let txPath = session.appendingPathComponent("transcript.txt")
        let smPath = session.appendingPathComponent("summary.md")

        guard FileManager.default.fileExists(atPath: txPath.path) else {
            return CLIResult(ok: false, error: "Transcript file not found")
        }

        logger.info("re-summarize: \(txPath.path)")

        do {
            let transcript = try String(contentsOf: txPath, encoding: .utf8)
            let customPrompt = SummarizationService.loadPromptProfile(profile)
            let summary = try await SummarizationService.summarize(
                transcript: transcript,
                backend: config.llmBackend,
                model: config.llmModel,
                ollamaHost: config.ollamaHost,
                prompt: customPrompt
            )
            try summary.write(to: smPath, atomically: true, encoding: .utf8)
            return CLIResult(ok: true, error: "")
        } catch {
            logger.error("re-summarize failed: \(error.localizedDescription)")
            return CLIResult(ok: false, error: error.localizedDescription)
        }
    }
}
