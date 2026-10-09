"""Build short material cues from documented CC0 recordings (macOS afconvert).
Usage: python3 tools/build_item_foley.py --cache /tmp/item-foley-sources
The source originals stay in the cache; only short processed WAVs ship.
"""
from pathlib import Path
import argparse, json, wave, struct, math, hashlib, urllib.request, subprocess
ROOT=Path(__file__).resolve().parents[1]
SR=44100

def read(p):
    with wave.open(str(p)) as w:
        assert w.getsampwidth()==2 and w.getnchannels()==1
        vals=struct.unpack('<'+'h'*w.getnframes(),w.readframes(w.getnframes()))
        return [v/32768 for v in vals]

def lowpass(v, a):
    result=[];y=0
    for x in v:y+=a*(x-y);result.append(y)
    return result

def excerpt(v,start,length,rate=1):
    return [v[min(len(v)-1,int((start+i/SR*rate)*SR))] for i in range(int(length*SR))]

def shape(v, peak=.55):
    avg=sum(v)/len(v);v=[x-avg for x in v]
    gain=peak/max(1e-6,max(abs(x) for x in v))
    return [x*gain*min(1,i/(SR*.004),(len(v)-1-i)/(SR*.045)) for i,x in enumerate(v)]

def write(path,v):
    with wave.open(str(path),'wb') as w:
        w.setparams((1,2,SR,0,'NONE','not compressed'))
        w.writeframes(struct.pack('<'+'h'*len(v),*(round(max(-.95,min(.95,x))*32767) for x in v)))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--cache',type=Path,required=True);args=parser.parse_args()
    meta=json.loads((ROOT/'assets/audio/interface/foley/sources.json').read_text())
    args.cache.mkdir(parents=True,exist_ok=True)
    raw={}
    for row in meta['sources']:
        p=args.cache/(row['id']+'.mp3');out=p.with_suffix('.wav')
        if not p.exists():
            req=urllib.request.Request(row['download'],headers={'User-Agent':'Mozilla/5.0'})
            p.write_bytes(urllib.request.urlopen(req,timeout=30).read())
        row['source_sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
        if not out.exists():subprocess.run(['/usr/bin/afconvert','-f','WAVE','-d','LEI16@44100','-c','1',str(p),str(out)],check=True)
        raw[row['id']]=read(out)
    # Base transients from recorded impacts; soft fruit/wood retain original project synthesis.
    for k in ['fruit','click']:
        p=ROOT/'assets/audio/interface'/f'{k}.wav'
        with wave.open(str(p)) as w:
            n=w.getframerate();v=struct.unpack('<'+'h'*w.getnframes(),w.readframes(w.getnframes()))
        raw[k]=[v[min(len(v)-1,int(i*n/SR))]/32768 for i in range(round(len(v)*SR/n))]
    # Strong short impact near start; long texture takes sampled from quiet, steady sections.
    starts={}
    for k in ['bottle','glass','ice','metal']:
        v=raw[k];peak=max(range(min(len(v),SR)),key=lambda i:abs(v[i]))
        starts[k]=max(0,peak/SR-.014)
    def base(k,j,length=.40,rate=1):
        start=starts.get(k,0)+(.018*j if k in starts else 0)
        if k=='leaf':start=2.3+j*5
        if k=='grain':start=4.2+j*3
        return excerpt(raw[k],start,length,rate)
    out=ROOT/'assets/audio/interface/foley';clips=[]
    families=['bottle','small_bottle','juice_bottle','fizzy_bottle','leaf','grain','fruit','cherry','glass','metal','wood','ice','crushed_ice']
    for family in families:
        for j in range(2):
            if family=='bottle':v=base('bottle',j,.38,1+j*.06)
            elif family=='small_bottle':v=base('bottle',j,.24,1.35+j*.08)
            elif family=='juice_bottle':v=lowpass(base('bottle',j,.36,.88+j*.05),.19)
            elif family=='fizzy_bottle':
                v=base('bottle',j,.42,1.14+j*.04);texture=shape(base('grain',j,.42),.08)
                v=[x+y for x,y in zip(v,texture)]
            elif family=='leaf':v=lowpass(base('leaf',j,.42),.36)
            elif family=='grain':v=base('grain',j,.38)
            elif family=='fruit':v=base('fruit',j,.27,1+j*.07)
            elif family=='cherry':v=base('fruit',j,.19,1.5+j*.09)
            elif family=='glass':v=base('glass',j,.55,.92+j*.06)
            elif family=='metal':v=base('metal',j,.32,1+j*.07)
            elif family=='wood':v=lowpass(base('click',j,.16,.8+j*.08),.12)
            elif family=='ice':v=base('ice',j,.46,.94+j*.08)
            else:
                v=base('ice',j,.50,1.45+j*.1)
                grain=shape(base('grain',j,.50),.10);v=[x+y for x,y in zip(v,grain)]
            v=shape(v,.42 if family in ['leaf','grain','fruit','cherry','wood'] else .55)
            for purchased in [False,True]:
                samples=v[:]
                if purchased:
                    start=len(samples)/SR-.06;samples += [0.] * int(.35*SR)
                    for offset,freq in [(start,1900),(start+.09,2450),(start+.16,2850)]:
                        for n in range(int(.14*SR)):
                            t=n/SR;idx=int(offset*SR)+n
                            samples[idx]+=.12*math.sin(2*math.pi*freq*t)*math.exp(-35*t)*min(1,t/.002)*max(0,1-t/.14)
                name=('purchase-' if purchased else '')+family+f'-{j+1}.wav';p=out/name;write(p,samples)
                clips.append({'file':name,'seconds':round(len(samples)/SR,3),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
    meta['clips']=clips
    meta['processing']='44.1 kHz mono PCM16; selected excerpts, DC removal, peak limit, 4ms attack / 45ms release. Variants use alternate excerpts or resampling; juice and leaves lowpass; fizzy/crushed combine recorded textures. Purchase adds original synthesized coin tail. See build_item_foley.py.'
    meta['excerpt_start_seconds']=starts
    (out/'sources.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
    print('Built',len(clips),'clips in',len(families),'material families')
