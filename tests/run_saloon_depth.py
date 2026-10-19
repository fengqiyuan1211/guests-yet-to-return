"""Verify saloon compositing with isolated saves; --graphics also captures all guests."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from run_workbench_liquid import SAVE_KEYS

parser = argparse.ArgumentParser()
parser.add_argument('--godot', required=True)
parser.add_argument('--graphics', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='saloon-depth-', dir='/tmp') as folder:
    command = [args.godot, '--audio-driver', 'Dummy']
    if not args.graphics:
        command.append('--headless')
    command += ['--path', str(root), 'tests/verify_saloon_depth.tscn', '--']
    command += [f'--{key}={folder}/{key}.json' for key in SAVE_KEYS]
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=60)
    print(result.stdout)
    if result.returncode or 'SCRIPT ERROR:' in result.stdout:
        raise SystemExit(result.returncode or 1)
