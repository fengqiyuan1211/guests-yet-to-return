"""Real shop, second drink and automatic first arrival; isolated saves."""
import argparse
import subprocess
import tempfile
from pathlib import Path
from run_workbench_liquid import SAVE_KEYS

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True)
parser.add_argument('--graphics', action='store_true')
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='recipe-unlock-', dir='/tmp') as folder:
    for mode in ('seed', 'resume', 'final'):
        cmd = [args.godot, '--audio-driver', 'Dummy']
        if not args.graphics:
            cmd += ['--headless']
        cmd += ['--path', str(Path(__file__).resolve().parents[1]),
                'tests/verify_opening_shop_lesson.tscn', '--']
        cmd += [f'--{key}={folder}/{key}.json' for key in SAVE_KEYS]
        cmd += ['--lesson-' + mode]
        try:
            result = subprocess.run(cmd, text=True, capture_output=True, timeout=90)
        except subprocess.TimeoutExpired as error:
            for output in (error.stdout,error.stderr):
                print(output.decode() if isinstance(output,bytes) else output,flush=True)
            raise
        print(result.stdout + result.stderr, flush=True)
        if result.returncode or 'SCRIPT ERROR:' in result.stderr:
            raise SystemExit(result.returncode or 1)
