import Foundation
import Darwin

enum AppState {
    case idle
    case recording
    case transcribing
    case summarizing
    case done(sessionPath: String)
    case error(String)
}

class TranscribeeRunner: ObservableObject {
    @Published var state: AppState = .idle

    private var currentProcess: Process?
    private let pidFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("transcribee-capture.pid")

    // MARK: - Binary discovery

    private func findBinary() -> String? {
        [
            (NSString("~/.local/bin/transcribee").expandingTildeInPath),
            "/usr/local/bin/transcribee",
        ].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Public API

    func start() {
        guard case .idle = state else { return }
        guard let bin = findBinary() else {
            state = .error("transcribee not installed — run install.sh")
            return
        }
        // Clean up any stale PID file
        try? FileManager.default.removeItem(at: pidFile)
        launchRecord(binary: bin)
    }

    func stop() {
        // Signal capture-bin directly via the PID file written by Python's capture.py
        // Retry up to 1s in case the file hasn't been written yet
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            for _ in 0..<20 {
                if let pidStr = try? String(contentsOf: pidFile),
                   let pid = pid_t(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                   pid > 0 {
                    kill(pid, SIGINT)
                    try? FileManager.default.removeItem(at: pidFile)
                    return
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            // Fallback: interrupt the Python wrapper process
            self.currentProcess?.interrupt()
        }
    }

    // MARK: - Pipeline steps

    private func launchRecord(binary: String) {
        let proc = makeProcess(binary: binary, args: ["record", "--pid-file", pidFile.path])
        var wavPath: String?

        attachReader(to: proc.standardOutput as! Pipe) { line in
            // "Saved: /path/to/audio.wav"
            if line.hasPrefix("Saved:") {
                wavPath = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            }
        }
        attachReader(to: proc.standardError as! Pipe) { _ in }

        proc.terminationHandler = { [weak self] p in
            guard let self else { return }
            DispatchQueue.main.async {
                if p.terminationStatus == 0, let wav = wavPath {
                    self.launchTranscribe(binary: binary, wavPath: wav)
                } else if p.terminationStatus != 0 {
                    if case .error = self.state { return }
                    self.state = .error("Recording failed (exit \(p.terminationStatus))")
                    NotificationManager.notifyError("Recording failed")
                }
                // exit 0 with no wav path: stopped before anything was written (ignore)
            }
        }

        runProcess(proc)
        state = .recording
    }

    private func launchTranscribe(binary: String, wavPath: String) {
        let sessionDir = URL(fileURLWithPath: wavPath).deletingLastPathComponent()
        let transcriptPath = sessionDir.appendingPathComponent("transcript.txt").path

        state = .transcribing
        let proc = makeProcess(binary: binary, args: ["transcribe", wavPath, "--out", transcriptPath])
        attachReader(to: proc.standardOutput as! Pipe) { _ in }
        attachReader(to: proc.standardError as! Pipe) { _ in }

        proc.terminationHandler = { [weak self] p in
            guard let self else { return }
            DispatchQueue.main.async {
                if p.terminationStatus == 0 {
                    self.launchSummarize(binary: binary, transcriptPath: transcriptPath, sessionDir: sessionDir)
                } else {
                    self.state = .error("Transcription failed")
                    NotificationManager.notifyError("Transcription failed")
                }
            }
        }
        runProcess(proc)
    }

    private func launchSummarize(binary: String, transcriptPath: String, sessionDir: URL) {
        let summaryPath = sessionDir.appendingPathComponent("summary.md").path

        state = .summarizing
        let proc = makeProcess(binary: binary, args: ["summarize", transcriptPath, "--out", summaryPath])
        attachReader(to: proc.standardOutput as! Pipe) { _ in }
        attachReader(to: proc.standardError as! Pipe) { _ in }

        proc.terminationHandler = { [weak self] p in
            guard let self else { return }
            DispatchQueue.main.async {
                // Done regardless of summarize exit code — transcript is what matters
                self.state = .done(sessionPath: sessionDir.path)
                NotificationManager.notifyDone(sessionPath: sessionDir.path)
            }
        }
        runProcess(proc)
    }

    // MARK: - Helpers

    private func makeProcess(binary: String, args: [String]) -> Process {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = args
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        return proc
    }

    private func runProcess(_ proc: Process) {
        do {
            try proc.run()
            currentProcess = proc
        } catch {
            DispatchQueue.main.async {
                self.state = .error("Failed to launch: \(error.localizedDescription)")
            }
        }
    }

    private func attachReader(to pipe: Pipe, handler: @escaping (String) -> Void) {
        var buf = Data()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            buf.append(chunk)
            while let nl = buf.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buf[buf.startIndex..<nl]
                buf.removeSubrange(buf.startIndex...nl)
                if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !line.isEmpty {
                    handler(line)
                }
            }
        }
    }
}
