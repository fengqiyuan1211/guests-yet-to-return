"""Original soft starlight cue for the harbor title buttons (no samples)."""
import math
import struct
import wave
from pathlib import Path

RATE = 44100
DURATION = 1.05
samples = []
for i in range(int(RATE * DURATION)):
    t = i / RATE
    value = 0.0
    # A quiet fundamental with faint, delayed fifth/octave glints.
    # Harmonic sine tones avoid the struck-glass/metallic attack of the first version.
    for start, frequency, gain in [(0.0, 1046.50, 0.75), (0.10, 1567.98, 0.13), (0.17, 2093.0, 0.07)]:
        age = t - start
        if age < 0:
            continue
        attack = (1.0 - math.exp(-age / 0.025)) ** 2
        value += gain * attack * math.exp(-age / 0.17) * math.sin(math.tau * frequency * age)
    # Smoothly silence the tail; no hard cut or DC step.
    value *= min(1.0, (DURATION - t) / 0.08)
    samples.append(value)
peak = max(abs(v) for v in samples)
path = Path(__file__).resolve().parents[1] / 'assets/audio/opening/button-shimmer.wav'
with wave.open(str(path), 'wb') as out:
    out.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
    out.writeframes(b''.join(struct.pack('<h', round(v / peak * 0.50 * 32767)) for v in samples))
print(path)
