"""Early character invitations, old saves, write recovery and process restart."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from run_workbench_liquid import SAVE_KEYS

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True)
parser.add_argument('--graphics', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='activity-unlocks-', dir='/tmp') as folder:
    for resume in (False, True):
        cmd = [args.godot] + ([] if args.graphics and not resume else ['--headless'])
        cmd += ['--path', str(root), 'tests/verify_activity_unlocks.tscn', '--']
        cmd += [f'--{key}={folder}/{key}.json' for key in SAVE_KEYS]
        if resume:
            cmd.append('--unlocks-resume')
        result = subprocess.run(cmd, timeout=60, capture_output=True, text=True)
        log = result.stdout + result.stderr
        print(log, flush=True)
        errors = [line for line in log.splitlines() if
                  line.startswith(('SCRIPT ERROR:', 'ERROR:'))
                  and 'resources still in use at exit' not in line]
        if result.returncode or errors:
            raise SystemExit(result.returncode or 1)
