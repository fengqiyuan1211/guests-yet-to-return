"""Receipt UI, durable protagonist identity and replay isolation in private saves."""
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
with tempfile.TemporaryDirectory(prefix='protagonist-name-', dir='/tmp') as folder:
    for mode in ['--name-seed', '--name-resume']:
        cmd = [a.godot, '--audio-driver', 'Dummy'] + ([] if a.graphics else ['--headless'])
        cmd += ['--path', str(root), 'tests/verify_protagonist_name.tscn', '--', mode]
        cmd += [f'--{key}={folder}/{key}.json' for key in SAVE_KEYS]
        result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=45)
        print(result.stdout, flush=True)
        if result.returncode or 'SCRIPT ERROR:' in result.stdout:
            raise SystemExit(result.returncode or 1)
