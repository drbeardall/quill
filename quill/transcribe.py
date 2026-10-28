"""Local Whisper transcription.

Apple Silicon: mlx-whisper (runs on the GPU, fast).
Intel Macs: faster-whisper on CPU.
Audio never leaves the machine.
"""
from __future__ import annotations

import platform

import numpy as np

MLX_MODELS = {
    "auto": "mlx-community/whisper-large-v3-turbo",
    "large-v3-turbo": "mlx-community/whisper-large-v3-turbo",
    "small.en": "mlx-community/whisper-small.en-mlx",
    "base.en": "mlx-community/whisper-base.en-mlx",
}


class Transcriber:
    def __init__(self, model: str = "auto", language: str = "en", log=print) -> None:
        self.language = language or None
        self.log = log
        self.backend = None
        if platform.machine() == "arm64":
            try:
                import mlx_whisper  # noqa: F401

                self.backend = "mlx"
                self.model = MLX_MODELS.get(model, model)
            except ImportError:
                pass
        if self.backend is None:
            from faster_whisper import WhisperModel

            name = "small.en" if model == "auto" else model
            self.backend = "faster"
            self.model = name
            self._fw = WhisperModel(name, device="cpu", compute_type="int8")
        self.log(f"Whisper backend: {self.backend} ({self.model})")

    def warm_up(self) -> None:
        """Load model weights now so the first dictation isn't slow."""
        self.transcribe(np.zeros(16000, dtype=np.float32))

    def transcribe(self, audio: np.ndarray, prompt: str = "") -> str:
        audio = audio.astype(np.float32)
        if self.backend == "mlx":
            import mlx_whisper

            result = mlx_whisper.transcribe(
                audio,
                path_or_hf_repo=self.model,
                language=self.language,
                initial_prompt=prompt or None,
                condition_on_previous_text=False,
            )
            return (result.get("text") or "").strip()

        segments, _info = self._fw.transcribe(
            audio,
            language=self.language,
            initial_prompt=prompt or None,
            vad_filter=True,
            beam_size=5,
        )
        return " ".join(s.text.strip() for s in segments).strip()
