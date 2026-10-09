"""Deterministic original synthesized water, wind, clock and warm completion accents.
Contact foley remains the project's credited wood/metal recordings; no new remote samples.
"""
from pathlib import Path
import math, random, struct, wave
ROOT=Path(__file__).resolve().parents[1]/'assets/audio/activities'
ROOT.mkdir(parents=True,exist_ok=True)
rate=22050
for name,duration in [('water',.85),('wind',2.0),('tick',.13),('success',1.5)]:
    rng=random.Random(823); samples=[]; low=0
    for i in range(int(rate*duration)):
        t=i/rate; low=.92*low+.08*rng.uniform(-1,1)
        env=min(1,t*25)*min(1,(duration-t)*12)
        if name=='water': v=low*.7+math.sin(t*math.tau*(180+80*math.sin(t*13)))*.015
        elif name=='wind': v=low*.3*(.65+.35*math.sin(t*2))
        elif name=='tick': v=(rng.uniform(-1,1)*.10+math.sin(t*math.tau*1900)*.11)*math.exp(-t*65)
        else:
            v=0
            for j,f in enumerate([330,415.3,493.88,659.25]):
                u=t-j*.13
                if u>=0: v+=(math.sin(math.tau*f*u)+.18*math.sin(math.tau*f*2*u))*.1*math.exp(-u*3)*min(1,u*100)
        samples.append(struct.pack('<h',round(max(-1,min(1,v*env))*32767)))
    with wave.open(str(ROOT/(name+'.wav')),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(rate);w.writeframes(b''.join(samples))
