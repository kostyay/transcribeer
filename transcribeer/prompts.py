from __future__ import annotations

from pathlib import Path

from transcribeer.summarize import SYSTEM_PROMPT


def _prompts_dir() -> Path:
    return Path.home() / ".transcribeer" / "prompts"


def list_profiles() -> list[str]:
    """Return available profile names. 'default' is always first."""
    d = _prompts_dir()
    profiles = ["default"]
    if d.exists():
        extras = sorted(
            p.stem for p in d.glob("*.md")
            if p.is_file() and p.stem != "default"
        )
        profiles.extend(extras)
    return profiles


def load_prompt(name: str | None) -> str:
    """Return prompt text for profile `name`. None/'default' with no file → SYSTEM_PROMPT."""
    if not name or name == "default":
        p = _prompts_dir() / "default.md"
        return p.read_text(encoding="utf-8") if p.exists() else SYSTEM_PROMPT
    p = _prompts_dir() / f"{name}.md"
    return p.read_text(encoding="utf-8") if p.exists() else SYSTEM_PROMPT
