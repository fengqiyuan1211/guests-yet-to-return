"""Playable character loops and separate-process restore, with isolated saves."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from run_workbench_liquid import SAVE_KEYS

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True)
parser.add_argument('--graphics', action='store_true')
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='character-activities-', dir='/tmp') as folder:
    for resume in (False, True):
        cmd = [args.godot] + ([] if args.graphics and not resume else ['--headless'])
        cmd += ['--path', str(ROOT), 'tests/verify_character_activities.tscn', '--']
        cmd += [f'--{key}={folder}/{key}.json' for key in SAVE_KEYS]
        if resume:
            cmd.append('--activities-resume')
        result = subprocess.run(cmd, timeout=120)
        if result.returncode:
            raise SystemExit(result.returncode)
