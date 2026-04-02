import time
from pathlib import Path
import pytest


def test_new_session_creates_directory(tmp_path):
    from transcribeer.session import new_session
    path = new_session(sessions_dir=tmp_path / "sessions")
    assert path.exists()
    assert path.is_dir()


def test_new_session_name_format(tmp_path):
    """Directory name matches YYYY-MM-DD-HHMM."""
    import re
    from transcribeer.session import new_session
    path = new_session(sessions_dir=tmp_path / "sessions")
    assert re.match(r"\d{4}-\d{2}-\d{2}-\d{4}", path.name)


def test_latest_session_returns_most_recent(tmp_path):
    from transcribeer.session import new_session, latest_session
    sessions_dir = tmp_path / "sessions"
    first = new_session(sessions_dir=sessions_dir)
    time.sleep(0.05)
    second = new_session(sessions_dir=sessions_dir)
    assert latest_session(sessions_dir=sessions_dir) == second


def test_latest_session_returns_none_when_empty(tmp_path):
    from transcribeer.session import latest_session
    assert latest_session(sessions_dir=tmp_path / "sessions") is None
