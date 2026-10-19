"""Render the revised CGs and exercise held-key boundaries using isolated saves."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from run_workbench_liquid import SAVE_KEYS

p = argparse.ArgumentParser()
p.add_argument('--godot', required=True)
p.add_argument('--graphics', action='store_true')
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='opening-visual-', dir='/tmp') as folder:
    cmd = [a.godot, '--audio-driver', 'Dummy']
    if not a.graphics:
        cmd.append('--headless')
    cmd += ['--path', str(root), 'tests/verify_opening_visual_revision.tscn', '--']
    cmd += [f'--{key}={folder}/{key}.json' for key in SAVE_KEYS]
    try:
        result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=60)
    except subprocess.TimeoutExpired as error:
        print(error.stdout, flush=True)
        raise
    print(result.stdout)
    if result.returncode or 'SCRIPT ERROR:' in result.stdout:
        raise SystemExit(result.returncode or 1)
