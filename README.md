# transcribee

macOS audio capture, transcription, and summarization — CLI-first, Hebrew + English.

Captures both sides of a call via system audio (SCStream), transcribes with faster-whisper, optionally diarizes speakers, and summarizes with an LLM.

---

## Requirements

- macOS 13 (Ventura) or later, Apple Silicon (arm64)
- Python 3.11+
- [uv](https://github.com/astral-sh/uv)
- ffmpeg (`brew install ffmpeg`)

---

## Install

```bash
git clone https://github.com/your-org/transcribee
cd transcribee
bash install.sh
```

The installer will:
1. Check macOS version and architecture
2. Install ffmpeg if missing (via Homebrew)
3. Place `capture-bin` in `~/.transcribee/bin/`
4. Create a Python venv at `~/.transcribee/venv/`
5. Ask which diarization backend to install:
   - **pyannote** — best quality, requires a HuggingFace account and token
   - **resemblyzer** — no account needed, good quality
   - **none** — no speaker labels, fastest
6. Write a default config to `~/.transcribee/config.toml`
7. Symlink `transcribee` into `~/.local/bin/`

---

## Usage

### One-shot: record → transcribe → summarize

```bash
transcribee run
# or with a time limit:
transcribee run --duration 300   # auto-stop after 5 minutes
```

Press `Ctrl+C` to stop recording. Transcription and summarization run automatically.

Output saved to `~/.transcribee/sessions/YYYY-MM-DD-HHMM/`:
- `audio.wav`
- `transcript.txt`
- `summary.md`

### Record only

```bash
transcribee record                     # stop with Ctrl+C
transcribee record --duration 60       # stop after 60 seconds
transcribee record --out /tmp/call.wav # custom output path
```

macOS will prompt for **Screen & System Audio Recording** permission on first run.

### Transcribe an existing file

```bash
transcribee transcribe call.wav
transcribee transcribe call.wav --lang he          # force Hebrew
transcribee transcribe call.wav --no-diarize       # skip speaker labels
transcribee transcribe call.wav --out call.txt     # custom output path
```

Supported languages: `he` (Hebrew), `en` (English), `auto` (detect).

Output format:
```
[00:00 -> 00:08] Speaker 1: שלום, איך אתה?
[00:09 -> 00:15] Speaker 2: בסדר גמור, תודה.
```

### Summarize a transcript

```bash
transcribee summarize call.txt
transcribee summarize call.txt --backend openai    # override LLM backend
transcribee summarize call.txt --out call.md       # custom output path
```

---

## Configuration

`~/.transcribee/config.toml` is written by the installer. Edit it to change defaults:

```toml
[transcription]
language = "auto"          # auto, he, en
diarization = "resemblyzer" # pyannote, resemblyzer, none
num_speakers = 0           # 0 = auto-detect

[summarization]
backend = "ollama"         # ollama, openai, anthropic
model = "llama3"
ollama_host = "http://localhost:11434"

[paths]
sessions_dir = "~/.transcribee/sessions"
capture_bin = "~/.transcribee/bin/capture-bin"
```

### LLM backends

| Backend | Setup |
|---|---|
| `ollama` | Run [Ollama](https://ollama.ai) locally with a model pulled (`ollama pull llama3`) |
| `openai` | Set `OPENAI_API_KEY` in your environment |
| `anthropic` | Set `ANTHROPIC_API_KEY` in your environment |

---

## Models

| Component | Model |
|---|---|
| Transcription | `ivrit-ai/whisper-large-v3-turbo-ct2` (via faster-whisper) |
| Diarization (pyannote) | `ivrit-ai/pyannote-speaker-diarization-3.1` |

Models are downloaded from HuggingFace on first use and cached at `~/.cache/huggingface/`.

---

## Permission

On first `transcribee record` or `transcribee run`, macOS will request **Screen & System Audio Recording** permission. Grant it in **System Settings → Privacy & Security → Screen & System Audio Recording**.

---

## Development

```bash
git clone https://github.com/your-org/transcribee
cd transcribee
uv venv && source .venv/bin/activate
uv pip install -e ".[dev]"
pytest
```
