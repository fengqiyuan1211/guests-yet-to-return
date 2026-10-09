"""Merged story/free-mode/journal flow, isolated saves plus process restart."""
import argparse, subprocess, tempfile
from pathlib import Path
from run_workbench_liquid import SAVE_KEYS
p=argparse.ArgumentParser(); p.add_argument('--godot', required=True); p.add_argument('--graphics', action='store_true'); a=p.parse_args()
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='branch-integration-',dir='/tmp') as folder:
    for resume in (False,True):
        cmd=[a.godot]+([] if a.graphics and not resume else ['--headless'])+['--path',str(root),'tests/verify_branch_integration.tscn','--']+[f'--{key}={folder}/{key}.json' for key in SAVE_KEYS]
        if resume: cmd.append('--integration-resume')
        r=subprocess.run(cmd,timeout=120)
        if r.returncode: raise SystemExit(r.returncode)
