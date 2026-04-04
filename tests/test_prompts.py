from pathlib import Path
import pytest


def test_list_profiles_no_dir(monkeypatch, tmp_path):
    """No prompts dir → only 'default' returned."""
    monkeypatch.setenv("HOME", str(tmp_path))
    from transcribeer import prompts
    assert prompts.list_profiles() == ["default"]


def test_list_profiles_with_files(monkeypatch, tmp_path):
    """Prompt files appear sorted after 'default'."""
    d = tmp_path / ".transcribeer" / "prompts"
    d.mkdir(parents=True)
    (d / "standup.md").write_text("standup prompt")
    (d / "1on1.md").write_text("1on1 prompt")
    monkeypatch.setenv("HOME", str(tmp_path))
    from transcribeer import prompts
    result = prompts.list_profiles()
    assert result[0] == "default"
    assert result[1:] == ["1on1", "standup"]


def test_list_profiles_default_md_not_duplicated(monkeypatch, tmp_path):
    """A default.md file does not add a second 'default' entry."""
    d = tmp_path / ".transcribeer" / "prompts"
    d.mkdir(parents=True)
    (d / "default.md").write_text("custom default")
    monkeypatch.setenv("HOME", str(tmp_path))
    from transcribeer import prompts
    assert prompts.list_profiles().count("default") == 1


def test_load_prompt_none_returns_system_prompt(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    from transcribeer import prompts, summarize
    assert prompts.load_prompt(None) == summarize.SYSTEM_PROMPT


def test_load_prompt_default_no_file_returns_system_prompt(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    from transcribeer import prompts, summarize
    assert prompts.load_prompt("default") == summarize.SYSTEM_PROMPT


def test_load_prompt_default_file_overrides_system_prompt(monkeypatch, tmp_path):
    d = tmp_path / ".transcribeer" / "prompts"
    d.mkdir(parents=True)
    (d / "default.md").write_text("Custom default prompt")
    monkeypatch.setenv("HOME", str(tmp_path))
    from transcribeer import prompts
    assert prompts.load_prompt("default") == "Custom default prompt"


def test_load_prompt_named_file(monkeypatch, tmp_path):
    d = tmp_path / ".transcribeer" / "prompts"
    d.mkdir(parents=True)
    (d / "1on1.md").write_text("1on1 system prompt")
    monkeypatch.setenv("HOME", str(tmp_path))
    from transcribeer import prompts
    assert prompts.load_prompt("1on1") == "1on1 system prompt"


def test_load_prompt_unknown_name_returns_system_prompt(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    from transcribeer import prompts, summarize
    assert prompts.load_prompt("nonexistent") == summarize.SYSTEM_PROMPT
