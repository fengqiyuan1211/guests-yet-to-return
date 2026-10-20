"""Launch the actual prologue with a private profile and speaker jump buttons."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot', default=str(Path.home()/'Downloads/Godot.app/Contents/MacOS/Godot'))
p.add_argument('--merchant', action='store_true')
a = p.parse_args()
folder = Path(tempfile.mkdtemp(prefix='prologue-cast-demo-', dir='/tmp'))
keys = ('slot-wallet','dialogue-save','game-save','menu-save','supplies-save','workbench-save','audio-settings')
command = [a.godot,'--path',str(root),'tools/preview_opening_characters.tscn','--']
command += [f'--{k}={folder}/{k}.json' for k in keys]
if a.merchant:
    command.append('--merchant')
with (folder/'game.log').open('w') as log:
    process = subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
info = {'pid':process.pid,'save_folder':str(folder),'log':str(folder/'game.log')}
Path('/tmp/prologue-cast-demo-latest.json').write_text(json.dumps(info))
print(json.dumps(info,ensure_ascii=False,indent=2))
