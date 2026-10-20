"""Verify demo pacing and old-save recovery using private temporary saves."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
KEYS = ("slot-wallet", "dialogue-save", "game-save", "menu-save", "supplies-save",
        "workbench-save", "customer-save", "audio-settings")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="release-demo-", dir="/tmp") as folder:
        for resume in (False, True):
            command = [args.godot, "--headless", "--path", str(ROOT),
                       "--log-file", folder + "/godot.log",
                       "res://tests/verify_release_demo.tscn", "--",
                       "--no-local-services", "--feedback-url="]
            command += [f"--{key}={folder}/{key}.json" for key in KEYS]
            if resume:
                command.append("--demo-resume")
            result = subprocess.run(command, capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            print(output, flush=True)
            if result.returncode or "SCRIPT ERROR:" in output:
                raise SystemExit(result.returncode or 1)


if __name__ == "__main__":
    main()
