import AVFoundation
import Foundation

/// Represents a single recording session directory.
struct Session: Identifiable, Equatable {
    let id: String  // directory path
    let path: URL
    let name: String
    let isUntitled: Bool
    let date: Date
    let formattedDate: String
    let duration: String
    let snippet: String

    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
}

/// Detailed data for a selected session.
struct SessionDetail {
    let name: String
    let notes: String
    let date: String
    let duration: String
    let transcript: String
    let summary: String
    let canTranscribe: Bool
    let canSummarize: Bool
    let audioURL: URL?
}

// MARK: - Session Manager

enum SessionManager {
    /// List session dirs sorted most-recent first.
    static func listSessions(sessionsDir: String) -> [Session] {
        let dir = URL(fileURLWithPath: (sessionsDir as NSString).expandingTildeInPath)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles
        ) else { return [] }

        return contents
            .filter { url in
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                return isDir.boolValue
            }
            .sorted { a, b in
                let aDate = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let bDate = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return aDate > bDate
            }
            .map { sessionRow($0) }
    }

    /// Create a new session directory.
    static func newSession(sessionsDir: String) -> URL {
        let dir = URL(fileURLWithPath: (sessionsDir as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let name = formatter.string(from: Date())
        var path = dir.appendingPathComponent(name)
        var suffix = 0
        while FileManager.default.fileExists(atPath: path.path) {
            suffix += 1
            path = dir.appendingPathComponent("\(name)-\(suffix)")
        }
        try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    static func sessionRow(_ dir: URL) -> Session {
        let meta = readMeta(dir)
        let rawName = meta["name"] as? String ?? ""
        let displayName = rawName.isEmpty ? dir.lastPathComponent : rawName
        let creationDate = creationDate(of: dir)

        return Session(
            id: dir.path,
            path: dir,
            name: displayName,
            isUntitled: rawName.isEmpty,
            date: creationDate,
            formattedDate: dateFormatter.string(from: creationDate),
            duration: audioDuration(dir),
            snippet: snippet(dir)
        )
    }

    static func sessionDetail(_ dir: URL) -> SessionDetail {
        let meta = readMeta(dir)
        let txPath = dir.appendingPathComponent("transcript.txt")
        let smPath = dir.appendingPathComponent("summary.md")

        return SessionDetail(
            name: meta["name"] as? String ?? "",
            notes: meta["notes"] as? String ?? "",
            date: dateFormatter.string(from: creationDate(of: dir)),
            duration: audioDuration(dir),
            transcript: (try? String(contentsOf: txPath, encoding: .utf8)) ?? "",
            summary: (try? String(contentsOf: smPath, encoding: .utf8)) ?? "",
            canTranscribe: audioURL(in: dir) != nil,
            canSummarize: FileManager.default.fileExists(atPath: txPath.path),
            audioURL: audioURL(in: dir)
        )
    }

    // MARK: - Meta

    static func readMeta(_ dir: URL) -> [String: Any] {
        let path = dir.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    static func writeMeta(_ dir: URL, _ data: [String: Any]) {
        let path = dir.appendingPathComponent("meta.json")
        guard let jsonData = try? JSONSerialization.data(
            withJSONObject: data, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? jsonData.write(to: path, options: .atomic)
    }

    static func setName(_ dir: URL, _ name: String) {
        var data = readMeta(dir)
        data["name"] = name
        writeMeta(dir, data)
    }

    static func setNotes(_ dir: URL, _ notes: String) {
        var data = readMeta(dir)
        data["notes"] = notes
        writeMeta(dir, data)
    }

    static func displayName(_ dir: URL) -> String {
        let name = readMeta(dir)["name"] as? String ?? ""
        return name.isEmpty ? dir.lastPathComponent : name
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy HH:mm"
        return fmt
    }()

    private static func creationDate(of dir: URL) -> Date {
        (try? dir.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
    }

    /// Locate the audio file in a session directory (M4A preferred, WAV fallback).
    static func audioURL(in dir: URL) -> URL? {
        let m4a = dir.appendingPathComponent("audio.m4a")
        if FileManager.default.fileExists(atPath: m4a.path) { return m4a }
        let wav = dir.appendingPathComponent("audio.wav")
        if FileManager.default.fileExists(atPath: wav.path) { return wav }
        return nil
    }

    /// Audio duration using AVAudioFile — works for any Core Audio format.
    private static func audioDuration(_ dir: URL) -> String {
        guard let url = audioURL(in: dir),
              let file = try? AVAudioFile(forReading: url) else { return "—" }
        let seconds = Int(Double(file.length) / file.fileFormat.sampleRate)
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private static func snippet(_ dir: URL) -> String {
        for fname in ["summary.md", "transcript.txt"] {
            let path = dir.appendingPathComponent(fname)
            guard let text = try? String(contentsOf: path, encoding: .utf8) else { continue }
            if let first = text.components(separatedBy: .newlines)
                .lazy
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { !$0.isEmpty }) {
                return String(first.prefix(120))
            }
        }
        return ""
    }
}
