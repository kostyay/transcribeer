# tests/test_config.py
import os
import tempfile
from pathlib import Path
import pytest

def write_config(tmp_path: Path, content: str) -> Path:
    cfg = tmp_path / "config.toml"
    cfg.write_text(content)
    return cfg


def test_load_defaults(monkeypatch, tmp_path):
    """Missing config file → all defaults applied."""
    monkeypatch.setenv("HOME", str(tmp_path))
    from transcribeer.config import load, Config
    cfg = load()
    assert cfg.language == "auto"
    assert cfg.diarization == "resemblyzer"
    assert cfg.num_speakers is None  # 0 translated to None
    assert cfg.llm_backend == "ollama"
    assert cfg.llm_model == "llama3"
    assert cfg.ollama_host == "http://localhost:11434"


def test_load_custom_language(monkeypatch, tmp_path):
    """Explicit language value is loaded."""
    cfg_dir = tmp_path / ".transcribeer"
    cfg_dir.mkdir()
    (cfg_dir / "config.toml").write_text('[transcription]\nlanguage = "he"\n')
    monkeypatch.setenv("HOME", str(tmp_path))
    from transcribeer import config as cfg_mod
    import importlib; importlib.reload(cfg_mod)
    from transcribeer.config import load
    cfg = load()
    assert cfg.language == "he"


def test_num_speakers_zero_becomes_none(monkeypatch, tmp_path):
    """num_speakers = 0 in TOML → None in Config."""
    cfg_dir = tmp_path / ".transcribeer"
    cfg_dir.mkdir()
    (cfg_dir / "config.toml").write_text('[transcription]\nnum_speakers = 0\n')
    monkeypatch.setenv("HOME", str(tmp_path))
    from transcribeer.config import load
    cfg = load()
    assert cfg.num_speakers is None


def test_num_speakers_nonzero(monkeypatch, tmp_path):
    """num_speakers = 2 in TOML → 2 in Config."""
    cfg_dir = tmp_path / ".transcribeer"
    cfg_dir.mkdir()
    (cfg_dir / "config.toml").write_text('[transcription]\nnum_speakers = 2\n')
    monkeypatch.setenv("HOME", str(tmp_path))
    from transcribeer.config import load
    cfg = load()
    assert cfg.num_speakers == 2


def test_paths_expanded(monkeypatch, tmp_path):
    """~ in path values is expanded."""
    monkeypatch.setenv("HOME", str(tmp_path))
    from transcribeer.config import load
    cfg = load()
    assert not str(cfg.sessions_dir).startswith("~")
    assert not str(cfg.capture_bin).startswith("~")
