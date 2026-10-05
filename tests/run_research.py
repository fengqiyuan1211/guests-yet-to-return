"""Research integration and new-process recovery, always using private /tmp saves."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
KEYS = ("slot-wallet", "dialogue-save", "game-save", "menu-save",
        "supplies-save", "workbench-save", "audio-settings")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--graphics", action="store_true")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="research-check-", dir="/tmp") as folder:
        for resume in (False, True):
            command = [args.godot]
            if not args.graphics or resume:
                command.append("--headless")
            command += ["--path", str(ROOT), "tests/verify_research.tscn", "--"]
            command += [f"--{key}={folder}/{key}.json" for key in KEYS]
            if resume:
                command.append("--research-resume")
            result = subprocess.run(command, timeout=45, check=False)
            if result.returncode:
                raise SystemExit(result.returncode)
    print("Research integration and restart checks passed.")


if __name__ == "__main__":
    main()
