import SwiftUI

/// Renders a parsed transcript as a stack of speaker rows with clickable
/// timestamps. Tapping a timestamp seeks the session's audio player.
///
/// Intended to replace the raw `Text(detail.transcript)` dump. The source of
/// truth is still the plain-text `transcript.txt` on disk — this view parses
/// on the fly so export and copy-paste stay compatible with older sessions.
struct TranscriptView: View {
    /// Either the cleaned disk transcript or the live preview.
    let lines: [TranscriptLine]

    /// Called when the user clicks a `[MM:SS]` badge. Receives the segment
    /// start time in seconds.
    let onSeek: (Double) -> Void

    /// Optional: when non-nil, the row containing this time gets the "now
    /// playing" highlight. Pass the audio player's current time.
    let playheadTime: Double?

    /// When true, shows a subtle placeholder row at the bottom to signal more
    /// text is arriving. Used during live transcription.
    let isStreaming: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(lines) { line in
                        TranscriptRow(
                            line: line,
                            isActive: isActive(line),
                            onSeek: onSeek,
                        )
                        .id(line.id)
                    }

                    if isStreaming {
                        streamingIndicator
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: lines.count) { _, _ in
                guard isStreaming, let last = lines.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func isActive(_ line: TranscriptLine) -> Bool {
        guard let t = playheadTime else { return false }
        return t >= line.start && t < line.end
    }

    private var streamingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Listening…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

// MARK: - Row

private struct TranscriptRow: View {
    let line: TranscriptLine
    let isActive: Bool
    let onSeek: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    onSeek(line.start)
                } label: {
                    Text(formatTimestamp(line.start))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor.opacity(0.1)),
                        )
                }
                .buttonStyle(.plain)
                .help("Jump to \(formatTimestamp(line.start))")

                Text(line.speaker)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(speakerColor(for: line.speaker))
            }

            Text(line.text)
                .font(.system(size: 13))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear),
        )
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Stable speaker → color mapping. `Speaker 1`, `Speaker 2`, ... get
    /// distinct accents; `???` (unknown) stays muted.
    private func speakerColor(for speaker: String) -> Color {
        guard speaker != "???" else { return .secondary }
        let palette: [Color] = [.blue, .purple, .teal, .orange, .pink, .indigo, .green]
        let hash = abs(speaker.hashValue)
        return palette[hash % palette.count]
    }
}
