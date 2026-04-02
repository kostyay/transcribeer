class Transcribeer < Formula
  desc "Local-first meeting transcription and summarization for macOS"
  homepage "https://github.com/moshebeladev/transcribeer"
  url "https://github.com/moshebeladev/transcribeer/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256_UPDATE_BEFORE_RELEASE"
  license "MIT"

  depends_on "ffmpeg"
  depends_on "python@3.11"
  depends_on :macos => :ventura

  def install
    # Install script handles venv, package, and binary setup
    ENV["TRANSCRIBEER_NONINTERACTIVE"] = "1"
    system "./install.sh"
  end

  def caveats
    <<~EOS
      Transcribeer has been installed.

      First run:
        transcribeer-gui       # launch the menubar app
        transcribeer --help    # CLI usage

      To configure your LLM backend (Ollama/OpenAI/Anthropic) and diarization:
        ~/.transcribeer/config.toml

      Note: The first transcription will download the Whisper model (~1.5 GB).
      This happens automatically on first use.

      Recording consent: You are responsible for complying with all applicable
      laws regarding recording of conversations in your jurisdiction.
    EOS
  end

  test do
    system "#{bin}/transcribeer", "--help"
  end
end
