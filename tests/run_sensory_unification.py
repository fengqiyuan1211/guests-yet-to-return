"""Unified sensory model and persisted results, using isolated player saves."""
import argparse, subprocess, tempfile
from pathlib import Path
from run_workbench_liquid import SAVE_KEYS
p=argparse.ArgumentParser(); p.add_argument('--godot',required=True); a=p.parse_args()
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='sensory-unification-',dir='/tmp') as folder:
    for resume in (False,True):
        cmd=[a.godot,'--headless','--path',str(root),'tests/verify_sensory_unification.tscn','--']+[f'--{key}={folder}/{key}.json' for key in SAVE_KEYS]
        if resume: cmd.append('--resume-check')
        result=subprocess.run(cmd,timeout=120)
        if result.returncode: raise SystemExit(result.returncode)
