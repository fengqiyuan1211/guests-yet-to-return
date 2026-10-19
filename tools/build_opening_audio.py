"""Original restrained room music + mail cue; Python standard library only."""
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'assets/audio/opening'
RATE = 22050

def save(name, samples, peak):
    scale = peak / max(0.001, max(abs(v) for v in samples))
    with wave.open(str(ROOT / name), 'wb') as w:
        w.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        w.writeframes(b''.join(struct.pack('<h', round(max(-1, min(1, v * scale)) * 32767)) for v in samples))

def note(buffer, at, midi, gain, length=4.8):
    freq = 440 * 2 ** ((midi - 69) / 12)
    for i in range(int(length * RATE)):
        t = i / RATE
        k = int(at * RATE) + i
        if k >= len(buffer): break
        attack = min(1, t / .045) ** 2
        env = attack * math.exp(-t / 1.65) * min(1, (length-t)/.4)
        phase = 2 * math.pi * freq * t
        tone = math.sin(phase) + .16 * math.sin(2*phase) * math.exp(-t) + .025 * math.sin(3*phase)
        buffer[k] += gain * tone * env

music = [0.] * (RATE * 40)
# Am(add9), Fmaj7, Cmaj7, Gsus2: sparse notes, long spaces, no dramatic accents.
for bar, chord in enumerate([(45,57,60,64,71),(41,57,60,64,69),(48,55,59,64,67),(43,55,57,62,67)]):
    at = bar * 10 + .4
    note(music, at, chord[0], .14, 7)
    for offset, key, gain in [(1.0,chord[1],.25),(2.9,chord[2],.22),(4.9,chord[3],.20),(6.8,chord[4],.16)]:
        note(music, at+offset, key, gain)
for i in range(len(music)):
    music[i] *= min(1, i/(RATE*1.2), (len(music)-i)/(RATE*2.5))
save('quiet-room.wav', music, .40)

mail = [0.] * int(RATE * .85)
note(mail, 0, 76, .2, .65)
note(mail, .16, 83, .12, .65)
for i in range(len(mail)): mail[i] *= min(1, (len(mail)-i)/(RATE*.3))
save('mail-arrival.wav', mail, .38)
print('Built quiet-room.wav and mail-arrival.wav')
