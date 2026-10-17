"""Opening + tutorial integration, private saves and process recovery."""
import argparse, subprocess, tempfile
from pathlib import Path
from run_workbench_liquid import SAVE_KEYS
p=argparse.ArgumentParser();p.add_argument('--godot',required=True);p.add_argument('--graphics',action='store_true');a=p.parse_args()
r=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='opening-integration-',dir='/tmp') as folder:
    for mode in ('--opening-seed','--opening-resume'):
        cmd=[a.godot]+([] if a.graphics else ['--headless'])+['--path',str(r),'tests/verify_opening.tscn','--']+[f'--{k}={folder}/{k}.json' for k in SAVE_KEYS]+[mode]
        result=subprocess.run(cmd,timeout=60,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        print(result.stdout,flush=True)
        if result.returncode or 'SCRIPT ERROR:' in result.stdout or 'Shader compilation failed' in result.stdout:
            raise SystemExit(result.returncode or 1)
    # Simulate an existing profile from before the opening subsystem existed.
    import json
    opening=Path(folder)/'game-save.json.opening'
    opening.unlink()
    preserved={k:(Path(folder)/(k+'.json')).read_bytes() for k in SAVE_KEYS if k!='audio-settings' and (Path(folder)/(k+'.json')).exists()}
    cmd=[a.godot,'--headless','--path',str(r),'--quit-after','30','--']+[f'--{k}={folder}/{k}.json' for k in SAVE_KEYS]
    result=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=30)
    assert result.returncode==0 and 'SCRIPT ERROR:' not in result.stdout, result.stdout
    state=json.loads(opening.read_text())
    assert state['phase']=='ready' and state['legacy'], state
    for k,data in preserved.items():
        assert (Path(folder)/(k+'.json')).read_bytes()==data, f'Legacy title changed {k}'
    print('LEGACY TITLE: old profile preserved; continue enabled.')
with tempfile.TemporaryDirectory(prefix='opening-first-launch-',dir='/tmp') as folder:
    for launch in range(2):
        cmd=[a.godot,'--headless','--path',str(r),'--quit-after','30','--']+[f'--{k}={folder}/{k}.json' for k in SAVE_KEYS]
        result=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=30)
        assert result.returncode==0 and 'SCRIPT ERROR:' not in result.stdout,result.stdout
        state=json.loads((Path(folder)/'game-save.json.opening').read_text())
        assert state['phase']=='new' and not state['legacy'],state
    print('FIRST LAUNCH: quitting title and returning does not skip the opening.')
