import Testing
@testable import TranscribeerApp

struct TranscriptFormatterTests {

    // MARK: - formatTimestamp

    @Test("Formats seconds as MM:SS",
          arguments: [
              (0.0, "00:00"),
              (5.0, "00:05"),
              (65.0, "01:05"),
              (3661.0, "61:01"),
          ])
    func formatTimestamp(input: Double, expected: String) {
        #expect(TranscriptFormatter.formatTimestamp(input) == expected)
    }

    @Test("Fractional seconds are truncated, not rounded")
    func fractionalSecondsFloor() {
        #expect(TranscriptFormatter.formatTimestamp(59.9) == "00:59")
        #expect(TranscriptFormatter.formatTimestamp(0.999) == "00:00")
    }

    // MARK: - assignSpeakers

    @Test("Each whisper segment gets the speaker with most overlap")
    func assignByOverlap() {
        let whisper = [
            TranscriptSegment(start: 0, end: 10, text: "Hello"),
            TranscriptSegment(start: 10, end: 20, text: "World"),
        ]
        let diar = [
            DiarSegment(start: 0, end: 12, speaker: "A"),
            DiarSegment(start: 8, end: 20, speaker: "B"),
        ]
        let result = TranscriptFormatter.assignSpeakers(
            whisperSegments: whisper, diarSegments: diar
        )
        #expect(result.count == 2)
        // 0-10 overlaps A by 10s, B by 2s → A
        #expect(result[0].speaker == "A")
        // 10-20 overlaps A by 2s, B by 10s → B
        #expect(result[1].speaker == "B")
    }

    @Test("Falls back to midpoint containment when no overlap")
    func midpointFallback() {
        let whisper = [TranscriptSegment(start: 5, end: 7, text: "Gap")]
        let diar = [
            DiarSegment(start: 0, end: 4, speaker: "X"),
            DiarSegment(start: 5.5, end: 6.5, speaker: "Y"),
        ]
        let result = TranscriptFormatter.assignSpeakers(
            whisperSegments: whisper, diarSegments: diar
        )
        // midpoint is 6.0, contained in Y (5.5-6.5)
        #expect(result[0].speaker == "Y")
    }

    @Test("Empty diarization segments → all UNKNOWN")
    func emptyDiarization() {
        let whisper = [
            TranscriptSegment(start: 0, end: 5, text: "Solo"),
        ]
        let result = TranscriptFormatter.assignSpeakers(
            whisperSegments: whisper, diarSegments: []
        )
        #expect(result[0].speaker == "UNKNOWN")
    }

    @Test("Empty whisper segments → empty result")
    func emptyWhisper() {
        let diar = [DiarSegment(start: 0, end: 10, speaker: "A")]
        let result = TranscriptFormatter.assignSpeakers(
            whisperSegments: [], diarSegments: diar
        )
        #expect(result.isEmpty)
    }

    // MARK: - format

    @Test("Formats segments with timestamps and speaker labels")
    func basicFormatting() {
        let segments = [
            LabeledSegment(start: 0, end: 30, speaker: "SPK_0", text: "Hi there"),
            LabeledSegment(start: 30, end: 65, speaker: "SPK_1", text: "Hello"),
        ]
        let output = TranscriptFormatter.format(segments)
        let lines = output.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[0] == "[00:00 -> 00:30] Speaker 1: Hi there")
        #expect(lines[1] == "[00:30 -> 01:05] Speaker 2: Hello")
    }

    @Test("Merges consecutive segments from the same speaker")
    func mergeConsecutive() {
        let segments = [
            LabeledSegment(start: 0, end: 5, speaker: "A", text: "First"),
            LabeledSegment(start: 5, end: 10, speaker: "A", text: "second"),
            LabeledSegment(start: 10, end: 15, speaker: "B", text: "reply"),
        ]
        let output = TranscriptFormatter.format(segments)
        let lines = output.components(separatedBy: "\n")
        #expect(lines.count == 2, "Two speakers → two output lines after merge")
        #expect(lines[0].contains("First second"))
        #expect(lines[0].contains("[00:00 -> 00:10]"))
    }

    @Test("UNKNOWN speaker renders as ???")
    func unknownSpeaker() {
        let segments = [
            LabeledSegment(start: 0, end: 5, speaker: "UNKNOWN", text: "Mystery"),
        ]
        let output = TranscriptFormatter.format(segments)
        #expect(output.contains("???"))
    }

    @Test("Empty segments → empty string")
    func emptySegments() {
        #expect(TranscriptFormatter.format([]) == "")
    }

    @Test("Speaker numbering is stable (first-seen order)")
    func speakerNumbering() {
        let segments = [
            LabeledSegment(start: 0, end: 5, speaker: "Z", text: "a"),
            LabeledSegment(start: 5, end: 10, speaker: "A", text: "b"),
            LabeledSegment(start: 10, end: 15, speaker: "Z", text: "c"),
        ]
        let output = TranscriptFormatter.format(segments)
        // Z seen first → Speaker 1, A seen second → Speaker 2
        #expect(output.contains("Speaker 1: a"))
        #expect(output.contains("Speaker 2: b"))
        #expect(output.contains("Speaker 1: c"))
    }
}
