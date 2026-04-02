import subprocess
from pathlib import Path
from unittest.mock import patch, MagicMock
import pytest


def _make_config(tmp_path):
    from transcribeer.config import Config
    return Config(
        language="auto",
        diarization="none",
        num_speakers=None,
        llm_backend="ollama",
        llm_model="llama3",
        ollama_host="http://localhost:11434",
        sessions_dir=tmp_path / "sessions",
        capture_bin=tmp_path / "capture-bin",
    )


def test_record_builds_positional_args(tmp_path):
    """Calls capture-bin with positional args: <out_path> [duration]."""
    cfg = _make_config(tmp_path)
    out = tmp_path / "audio.wav"

    mock_proc = MagicMock()
    mock_proc.pid = 1234
    mock_proc.communicate.return_value = (b"", b"")
    mock_proc.returncode = 0

    with patch("subprocess.Popen", return_value=mock_proc) as mock_popen:
        from transcribeer.capture import record
        record(out_path=out, duration=60, pid_file=None, config=cfg)

    cmd = mock_popen.call_args[0][0]
    assert str(cfg.capture_bin) == cmd[0]
    assert str(out) == cmd[1]
    assert "60" == cmd[2]


def test_record_no_duration_omits_third_arg(tmp_path):
    """Without duration, only two positional args passed."""
    cfg = _make_config(tmp_path)
    out = tmp_path / "audio.wav"

    mock_proc = MagicMock()
    mock_proc.pid = 1234
    mock_proc.communicate.return_value = (b"", b"")
    mock_proc.returncode = 0

    with patch("subprocess.Popen", return_value=mock_proc) as mock_popen:
        from transcribeer.capture import record
        record(out_path=out, duration=None, pid_file=None, config=cfg)

    cmd = mock_popen.call_args[0][0]
    assert len(cmd) == 2


def test_record_writes_pidfile(tmp_path):
    """PID written to pidfile before blocking."""
    cfg = _make_config(tmp_path)
    out = tmp_path / "audio.wav"
    pid_file = tmp_path / "record.pid"

    mock_proc = MagicMock()
    mock_proc.pid = 9999
    mock_proc.communicate.return_value = (b"", b"")
    mock_proc.returncode = 0

    with patch("subprocess.Popen", return_value=mock_proc):
        from transcribeer.capture import record
        record(out_path=out, duration=None, pid_file=pid_file, config=cfg)

    assert pid_file.read_text() == "9999"


def test_permission_error_raised_on_scstream_denial(tmp_path):
    """Exit 1 + 'Screen & System Audio Recording' in stderr → PermissionError."""
    cfg = _make_config(tmp_path)
    out = tmp_path / "audio.wav"

    mock_proc = MagicMock()
    mock_proc.pid = 1234
    mock_proc.communicate.return_value = (
        b"",
        b'Grant "Screen & System Audio Recording" to your terminal',
    )
    mock_proc.returncode = 1

    with patch("subprocess.Popen", return_value=mock_proc):
        from transcribeer.capture import record
        with pytest.raises(PermissionError, match="Screen & System Audio Recording"):
            record(out_path=out, duration=None, pid_file=None, config=cfg)


def test_capture_bin_not_found_raises(tmp_path):
    """Missing capture-bin → FileNotFoundError."""
    cfg = _make_config(tmp_path)
    out = tmp_path / "audio.wav"

    with patch("subprocess.Popen", side_effect=FileNotFoundError):
        from transcribeer.capture import record
        with pytest.raises(FileNotFoundError):
            record(out_path=out, duration=None, pid_file=None, config=cfg)
