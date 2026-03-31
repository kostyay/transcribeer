from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass
from pathlib import Path

_DEFAULTS = {
    "transcription": {
        "language": "auto",
        "diarization": "resemblyzer",
        "num_speakers": 0,
    },
    "summarization": {
        "backend": "ollama",
        "model": "llama3",
        "ollama_host": "http://localhost:11434",
    },
    "paths": {
        "sessions_dir": "~/.transcribee/sessions",
        "capture_bin": "~/.transcribee/bin/capture-bin",
    },
}


@dataclass
class Config:
    language: str
    diarization: str
    num_speakers: int | None
    llm_backend: str
    llm_model: str
    ollama_host: str
    sessions_dir: Path
    capture_bin: Path


def load() -> Config:
    """Load ~/.transcribee/config.toml. Missing keys use defaults. Never raises."""
    config_path = Path.home() / ".transcribee" / "config.toml"
    data: dict = {}
    if config_path.exists():
        with open(config_path, "rb") as f:
            data = tomllib.load(f)

    def get(section: str, key: str):
        return data.get(section, {}).get(key, _DEFAULTS[section][key])

    raw_speakers = get("transcription", "num_speakers")
    num_speakers = None if raw_speakers == 0 else int(raw_speakers)

    return Config(
        language=get("transcription", "language"),
        diarization=get("transcription", "diarization"),
        num_speakers=num_speakers,
        llm_backend=get("summarization", "backend"),
        llm_model=get("summarization", "model"),
        ollama_host=get("summarization", "ollama_host"),
        sessions_dir=Path(get("paths", "sessions_dir")).expanduser(),
        capture_bin=Path(get("paths", "capture_bin")).expanduser(),
    )
