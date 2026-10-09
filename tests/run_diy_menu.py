"""DIY menu integration + separate process restore; all seven saves isolated from the player."""
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
with tempfile.TemporaryDirectory(prefix='diy-menu-', dir='/tmp') as folder:
    for resume in (False, True):
        command = [args.godot] + ([] if args.graphics and not resume else ['--headless'])
        command += ['--path', str(ROOT), 'tests/verify_diy_menu.tscn', '--']
        command += [f'--{key}={folder}/{key}.json' for key in SAVE_KEYS]
        if resume:
            command += ['--research-resume']
        result = subprocess.run(command, timeout=60)
        if result.returncode:
            raise SystemExit(result.returncode)
