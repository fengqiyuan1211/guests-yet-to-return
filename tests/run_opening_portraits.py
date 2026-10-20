"""Speaker portraits and scene controls, exclusively using isolated saves."""
import argparse
import subprocess
import tempfile
from pathlib import Path
from run_workbench_liquid import SAVE_KEYS

p = argparse.ArgumentParser()
p.add_argument('--godot', required=True)
p.add_argument('--graphics', action='store_true')
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='opening-portraits-', dir='/tmp') as folder:
    cmd = [a.godot, '--audio-driver', 'Dummy']
    if not a.graphics:
        cmd.append('--headless')
    cmd += ['--path', str(root), 'tests/verify_opening_portraits.tscn', '--']
    cmd += [f'--{key}={folder}/{key}.json' for key in SAVE_KEYS]
    result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=90)
    print(result.stdout)
    if result.returncode or 'SCRIPT ERROR:' in result.stdout or 'OPENING PORTRAITS:' not in result.stdout:
        raise SystemExit(result.returncode or 1)
