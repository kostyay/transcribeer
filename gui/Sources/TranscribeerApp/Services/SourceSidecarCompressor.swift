import Foundation
import TranscribeerCore

/// Compresses raw per-source CAF recordings into compact M4A sidecars.
///
/// The app still captures to CAF because append-only PCM is reliable during a
/// live recording. At session finalization, these raw sidecars are replaced by
/// `audio.mic.m4a` / `audio.sys.m4a` so later retranscription can preserve
/// source labels without keeping large PCM files around.
enum SourceSidecarCompressor {
    struct Report: Sendable, Equatable {
        var compressed: [FileReport] = []
        var skipped: [String] = []
        var failed: [String] = []

        var compressedCount: Int { compressed.count }
        var methods: [String] { Array(Set(compressed.map(\.method))).sorted() }
    }

    struct FileReport: Sendable, Equatable {
        let source: String
        let method: String
        let rawBytes: UInt64
        let compressedBytes: UInt64
    }

    static func compressSession(in session: URL, ffmpegPath: String) async -> Report {
        let service = AudioProcessingService(configuredFFmpegPath: ffmpegPath)
        return await compressSession(in: session, service: service)
    }

    static func compressSession(
        in session: URL,
        service: AudioProcessingService
    ) async -> Report {
        await Task.detached(priority: .utility) {
            await compressSessionWork(in: session, service: service)
        }.value
    }

    private static func compressSessionWork(
        in session: URL,
        service: AudioProcessingService
    ) async -> Report {
        var report = Report()

        for source in SourceAudioFiles.Source.allCases {
            let raw = SourceAudioFiles.rawURL(in: session, source: source)
            let compressed = SourceAudioFiles.compressedURL(in: session, source: source)
            guard SourceAudioFiles.isNonEmpty(raw) else {
                report.skipped.append(source.rawValue)
                continue
            }

            do {
                let file = try await compress(raw: raw, compressed: compressed, service: service)
                report.compressed.append(FileReport(
                    source: source.rawValue,
                    method: file.method,
                    rawBytes: file.rawBytes,
                    compressedBytes: file.compressedBytes
                ))
            } catch {
                report.failed.append("\(source.rawValue): \(error.localizedDescription)")
            }
        }

        return report
    }

    private struct CompressedFile {
        let method: String
        let rawBytes: UInt64
        let compressedBytes: UInt64
    }

    private static func compress(
        raw: URL,
        compressed: URL,
        service: AudioProcessingService
    ) async throws -> CompressedFile {
        let request = AudioTranscodeRequest(inputURL: raw, outputURL: compressed)
        let result = try await service.transcode(request)
        guard SourceAudioFiles.isNonEmpty(compressed) else {
            throw AudioProcessingError.emptyOutput(compressed)
        }
        return CompressedFile(
            method: result.backendID,
            rawBytes: fileSize(raw),
            compressedBytes: result.outputBytes
        )
    }

    private static func fileSize(_ url: URL) -> UInt64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return 0
        }
        return switch attributes[.size] {
        case let size as UInt64: size
        case let size as NSNumber: size.uint64Value
        default: 0
        }
    }
}
