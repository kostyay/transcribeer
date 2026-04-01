"""macOS menubar GUI using rumps."""
from __future__ import annotations

import signal
import subprocess
import threading
import time
from pathlib import Path

import rumps

from transcribee.config import load


class TranscribeeApp(rumps.App):
    def __init__(self):
        super().__init__("🎙", quit_button="Quit")
        self.cfg = load()
        self._thread: threading.Thread | None = None
        self._stop_event = threading.Event()
        self._capture_proc: subprocess.Popen | None = None
        self._sess: Path | None = None
        self._record_start: float | None = None

        # Pre-create all items with explicit callbacks — no @clicked magic
        self._status_item = rumps.MenuItem("", callback=None)
        self._open_item = rumps.MenuItem("📁 Open Session Dir", callback=self._on_open)
        self._stop_item = rumps.MenuItem("⏹ Stop Recording", callback=self._on_stop)
        self._start_item = rumps.MenuItem("Start Recording", callback=self._on_start)

        self.menu = [
            self._status_item,
            self._open_item,
            self._stop_item,
            None,  # separator
            self._start_item,
        ]

        # 1-second tick to update elapsed time while recording
        self._timer = rumps.Timer(self._tick, 1)
        self._timer.start()

        self._set_idle()

    # ── Timer ─────────────────────────────────────────────────────────────────

    def _tick(self, _timer):
        if self._record_start is not None and self._capture_proc is not None:
            elapsed = int(time.time() - self._record_start)
            m, s = divmod(elapsed, 60)
            self._status_item.title = f"⏺ Recording  {m:02d}:{s:02d}"

    # ── Menu callbacks ────────────────────────────────────────────────────────

    def _on_start(self, _):
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def _on_stop(self, _):
        self._stop_event.set()
        proc = self._capture_proc
        if proc:
            proc.send_signal(signal.SIGINT)
        # Disable stop button immediately so double-clicks don't re-fire
        self._stop_item.set_callback(None)

    def _on_open(self, _):
        if self._sess:
            subprocess.run(["open", str(self._sess)])

    # ── Pipeline (background thread) ─────────────────────────────────────────

    def _run(self):
        from transcribee import session, transcribe as tx, summarize as sm

        cfg = self.cfg
        sess = session.new_session(cfg.sessions_dir)
        self._sess = sess
        audio_path = sess / "audio.wav"
        transcript_path = sess / "transcript.txt"
        summary_path = sess / "summary.md"

        # 1. Record
        self._set_recording()
        try:
            self._capture_proc = subprocess.Popen(
                [str(cfg.capture_bin), str(audio_path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            _, stderr = self._capture_proc.communicate()
            rc = self._capture_proc.returncode
            self._capture_proc = None
            self._record_start = None

            if rc != 0 and not self._stop_event.is_set():
                err = stderr.decode("utf-8", errors="replace")
                if "Screen & System Audio Recording" in err:
                    return self._set_error("Grant Screen Recording in System Settings → Privacy")
                return self._set_error(f"capture-bin exited {rc}")

            if not audio_path.exists() or audio_path.stat().st_size == 0:
                return self._set_idle()
        except Exception as e:
            self._capture_proc = None
            self._record_start = None
            return self._set_error(str(e))

        # 2. Transcribe
        self._set_status("📝 Transcribing…")
        try:
            tx.run(
                audio_path=audio_path,
                language=cfg.language,
                diarize_backend=cfg.diarization,
                num_speakers=cfg.num_speakers,
                out_path=transcript_path,
            )
        except Exception as e:
            return self._set_error(f"Transcription failed: {e}")

        # 3. Summarize (best-effort)
        self._set_status("🤔 Summarizing…")
        try:
            summary = sm.run(
                transcript=transcript_path.read_text(encoding="utf-8"),
                backend=cfg.llm_backend,
                model=cfg.llm_model,
                ollama_host=cfg.ollama_host,
            )
            summary_path.write_text(summary, encoding="utf-8")
        except Exception:
            pass

        self._set_done()

    # ── State helpers (called from background thread — rumps/PyObjC is ok) ───

    def _set_idle(self):
        self.title = "🎙"
        self._status_item.hidden = True
        self._open_item.hidden = True
        self._stop_item.hidden = True
        self._start_item.hidden = False

    def _set_recording(self):
        self._record_start = time.time()
        self.title = "⏺"
        self._status_item.title = "⏺ Recording  00:00"
        self._status_item.hidden = False
        self._open_item.hidden = False
        self._stop_item.hidden = False
        self._stop_item.set_callback(self._on_stop)  # re-arm after any previous disable
        self._start_item.hidden = True

    def _set_status(self, label: str):
        self.title = label.split()[0]
        self._status_item.title = label
        self._status_item.hidden = False
        self._open_item.hidden = False
        self._stop_item.hidden = True
        self._start_item.hidden = True

    def _set_done(self):
        self.title = "✓"
        self._status_item.title = "✓ Done"
        self._status_item.hidden = False
        self._open_item.hidden = False
        self._stop_item.hidden = True
        self._start_item.hidden = False
        rumps.notification("Transcribee", "Done", str(self._sess), sound=False)

    def _set_error(self, msg: str):
        self.title = "⚠"
        self._status_item.title = f"⚠ Error"
        self._status_item.hidden = False
        self._open_item.hidden = self._sess is None
        self._stop_item.hidden = True
        self._start_item.hidden = False
        rumps.alert(title="Transcribee Error", message=msg)


def main():
    TranscribeeApp().run()


if __name__ == "__main__":
    main()
