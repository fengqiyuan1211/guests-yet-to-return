"""Check B mint, soft layers and FIFO bottles using isolated saves."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from run_workbench_liquid import ROOT, SAVE_KEYS

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--godot", required=True)
parser.add_argument("--graphics", action="store_true")
args = parser.parse_args()
for scene in ("verify_workbench_b_polish", "verify_workbench_drag"):
    with tempfile.TemporaryDirectory(prefix="workbench-b-", dir="/tmp") as folder:
        command = [args.godot] + ([] if args.graphics else ["--headless"])
        command += ["--path", str(ROOT), f"tests/{scene}.tscn", "--"]
        command += [f"--{key}={folder}/{key}.json" for key in SAVE_KEYS]
        result = subprocess.run(command, timeout=60, capture_output=True, text=True)
        log = result.stdout + result.stderr
        print(scene, log, flush=True)
        # Existing headless shutdown resource warnings are separate from script/draw failures.
        errors = [line for line in log.splitlines()
                  if (line.startswith("ERROR:") or line.startswith("SCRIPT ERROR:"))
                  and "resources still in use at exit" not in line]
        if result.returncode or errors:
            raise SystemExit(result.returncode or 1)
print("B mint, layers and bottle checks passed.")
