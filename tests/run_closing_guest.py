"""Closing guest + separate process restore; all seven saves isolated from the player."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
from run_workbench_liquid import SAVE_KEYS

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True)
parser.add_argument('--graphics', action='store_true')
parser.add_argument('--legacy-save', action='store_true', help='Restore the older JTL closing-day format')
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='closing-guest-', dir='/tmp') as folder:
    for resume in (False, True):
        command = [args.godot] + ([] if args.graphics and not resume else ['--headless'])
        command += ['--path', str(ROOT), 'tests/verify_closing_guest.tscn', '--']
        command += [f'--{key}={folder}/{key}.json' for key in SAVE_KEYS]
        if resume and args.legacy_save:
            path = Path(folder) / 'game-save.json'
            saved = json.loads(path.read_text())
            saved['visit']['closing_pending'] = True
            saved['visit']['closing_day'] = saved['clock']['day']
            saved['clock']['day'] += 1
            saved['clock'].pop('closing_pending', None)
            path.write_text(json.dumps(saved, ensure_ascii=False))
        if resume:
            command += ['--closing-resume']
        result = subprocess.run(command, timeout=60)
        if result.returncode:
            raise SystemExit(result.returncode)
