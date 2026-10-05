"""Muddling gestures, sound, persistent mint damage and process-restart regression."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from run_workbench_liquid import ROOT, SAVE_KEYS

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--godot", required=True)
parser.add_argument("--graphics", action="store_true")
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="workbench-muddle-", dir="/tmp") as folder:
    for resume in (False, True):
        cmd = [args.godot] + ([] if args.graphics and not resume else ["--headless"])
        cmd += ["--path", str(ROOT), "tests/verify_workbench_muddle.tscn", "--"]
        cmd += [f"--{key}={folder}/{key}.json" for key in SAVE_KEYS]
        if resume:
            cmd.append("--muddle-resume")
        result = subprocess.run(cmd, timeout=60, capture_output=True, text=True)
        log = result.stdout + result.stderr
        print(log, flush=True)
        errors = [line for line in log.splitlines()
                  if (line.startswith("ERROR:") or line.startswith("SCRIPT ERROR:"))
                  and "resources still in use at exit" not in line]
        if result.returncode or errors:
            raise SystemExit(result.returncode or 1)
print("Muddling and restart checks passed.")
