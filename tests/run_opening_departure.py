"""Opening night, merchant conversations and real economy, with process restart."""
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
with tempfile.TemporaryDirectory(prefix='opening-departure-', dir='/tmp') as folder:
    for mode in ('--departure-seed', '--departure-resume', '--departure-final'):
        cmd = [a.godot] + ([] if a.graphics else ['--headless'])
        cmd += ['--path', str(root), 'tests/verify_opening_departure.tscn', '--']
        cmd += [f'--{key}={folder}/{key}.json' for key in SAVE_KEYS] + [mode]
        try:
            result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
        except subprocess.TimeoutExpired as error:
            print(error.stdout.decode() if isinstance(error.stdout, bytes) else error.stdout, flush=True)
            raise
        print(result.stdout, flush=True)
        if result.returncode or 'SCRIPT ERROR:' in result.stdout:
            raise SystemExit(result.returncode or 1)
