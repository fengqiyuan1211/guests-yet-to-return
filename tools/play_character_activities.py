"""Launch a playable private profile, opening Ada/Milo/Hank directly."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot',default=shutil.which('godot') or str(Path.home()/'Downloads/Godot.app/Contents/MacOS/Godot'))
parser.add_argument('--activity',choices=['ada_watch_memory','milo_ferry','hank_lantern'],default='ada_watch_memory')
args=parser.parse_args()
folder=Path(tempfile.mkdtemp(prefix='guest-character-v2-',dir='/tmp'))
keys=('slot-wallet','dialogue-save','game-save','menu-save','supplies-save','workbench-save','audio-settings')
command=[args.godot,'--path',str(ROOT),'tools/preview_character_activities.tscn','--']
command += [f'--{key}={folder}/{key}.json' for key in keys]
command += [f'--activity={args.activity}']
with (folder/'game.log').open('w') as log:
    process=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
info={'pid':process.pid,'save_folder':str(folder),'log':str(folder/'game.log'),'activity':args.activity}
Path('/tmp/guest-character-playtest-latest.json').write_text(json.dumps(info))
print(json.dumps(info,ensure_ascii=False,indent=2))
