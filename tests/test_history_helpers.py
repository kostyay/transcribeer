import wave, struct
from pathlib import Path
import pytest


def test_list_sessions_empty(tmp_path):
    from transcribeer.history_window import list_sessions
    assert list_sessions(tmp_path / "nosuchdir") == []


def test_list_sessions_sorted_recent_first(tmp_path):
    from transcribeer.history_window import list_sessions
    import time
    d = tmp_path / "sessions"
    d.mkdir()
    a = d / "2024-01-01-0900"; a.mkdir()
    time.sleep(0.02)
    b = d / "2024-01-02-0900"; b.mkdir()
    result = list_sessions(d)
    assert result[0] == b
    assert result[1] == a


def test_audio_duration_missing(tmp_path):
    from transcribeer.history_window import _audio_duration
    assert _audio_duration(tmp_path) == "—"


def test_audio_duration_valid(tmp_path):
    from transcribeer.history_window import _audio_duration
    p = tmp_path / "audio.wav"
    # write a minimal valid wav: 65 seconds at 8000 Hz mono 16-bit → "1:05"
    n_frames = 8000 * 65
    with wave.open(str(p), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(8000)
        wf.writeframes(struct.pack("<" + "h" * n_frames, *([0] * n_frames)))
    assert _audio_duration(tmp_path) == "1:05"


def test_set_notes_roundtrip(tmp_path):
    from transcribeer.meta import set_notes, read_meta
    set_notes(tmp_path, "my note")
    assert read_meta(tmp_path)["notes"] == "my note"


def test_set_notes_preserves_name(tmp_path):
    from transcribeer.meta import set_name, set_notes, read_meta
    set_name(tmp_path, "standup")
    set_notes(tmp_path, "important")
    assert read_meta(tmp_path)["name"] == "standup"
    assert read_meta(tmp_path)["notes"] == "important"
