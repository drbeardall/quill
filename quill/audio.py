"""Microphone recording at 16 kHz mono, the format Whisper expects."""
from __future__ import annotations

import threading

import numpy as np

SAMPLE_RATE = 16000


class Recorder:
    def __init__(self) -> None:
        import sounddevice as sd  # imported lazily so core tests don't need it

        self._sd = sd
        self._chunks: list[np.ndarray] = []
        self._lock = threading.Lock()
        self._stream = None

    def _callback(self, indata, frames, time_info, status) -> None:
        with self._lock:
            self._chunks.append(indata[:, 0].copy())

    def start(self) -> None:
        with self._lock:
            self._chunks = []
        self._stream = self._sd.InputStream(
            samplerate=SAMPLE_RATE, channels=1, dtype="float32", callback=self._callback
        )
        self._stream.start()

    def stop(self) -> np.ndarray:
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None
        with self._lock:
            if not self._chunks:
                return np.zeros(0, dtype=np.float32)
            return np.concatenate(self._chunks)


def is_speech(audio: np.ndarray, min_seconds: float = 0.3, rms_threshold: float = 0.004) -> bool:
    """Cheap guard against Whisper hallucinating text from silence."""
    if audio.size < SAMPLE_RATE * min_seconds:
        return False
    return float(np.sqrt(np.mean(np.square(audio)))) >= rms_threshold
