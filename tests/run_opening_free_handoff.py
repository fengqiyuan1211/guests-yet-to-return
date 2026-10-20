"""Already-stocked, zero-coin teaching + isolated replay through native Milo order/delivery."""
import argparse
import subprocess
import tempfile
from pathlib import Path
from run_workbench_liquid import SAVE_KEYS
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--godot',required=True)
p.add_argument('--graphics',action='store_true')
a=p.parse_args()
with tempfile.TemporaryDirectory(prefix='opening-free-',dir='/tmp') as folder:
    cmd=[a.godot,'--audio-driver','Dummy']+([] if a.graphics else ['--headless'])
    cmd+=['--path',str(Path(__file__).resolve().parents[1]),'tests/verify_opening_free_handoff.tscn','--']
    cmd += [f'--{key}={folder}/{key}.json' for key in SAVE_KEYS]
    result=subprocess.run(cmd,capture_output=True,text=True,timeout=180)
    print(result.stdout+result.stderr,flush=True)
    raise SystemExit(result.returncode or int('SCRIPT ERROR:' in result.stderr))
