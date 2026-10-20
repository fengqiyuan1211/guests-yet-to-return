"""Test confirmed covers with an isolated project, image directory and save files."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
KEYS = ("slot-wallet", "dialogue-save", "game-save", "menu-save", "supplies-save",
        "workbench-save", "customer-save", "audio-settings")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    name = "Codex-DIY-Image-Test-" + uuid.uuid4().hex
    try:
        with tempfile.TemporaryDirectory(prefix="diy-cover-", dir="/tmp") as folder:
            project = Path(folder)
            for entry in ("assets", "scripts", "scenes", "shaders", "data", "tests", "icon.svg"):
                (project / entry).symlink_to(ROOT / entry)
            config = (ROOT / "project.godot").read_text()
            config = config.replace("[application]", '[application]\nconfig/use_custom_user_dir=true\n'
                                    f'config/custom_user_dir_name="{name}"')
            (project / "project.godot").write_text(config)
            base = [args.godot, "--headless", "--path", folder,
                    "--log-file", folder + "/godot.log"]
            for extra in (["--editor", "--import"],
                          ["res://tests/verify_diy_cover.tscn", "--", "--no-local-services", "--feedback-url="]
                          + [f"--{key}={folder}/{key}.json" for key in KEYS]):
                result = subprocess.run(base + extra, capture_output=True, text=True, timeout=90)
                output = result.stdout + result.stderr
                print(output, flush=True)
                if result.returncode or "SCRIPT ERROR:" in output:
                    raise SystemExit(result.returncode or 1)
    finally:
        # macOS test user data is separate from the game's profile.
        private_data = Path.home() / "Library/Application Support" / name
        if private_data.is_dir():
            shutil.rmtree(private_data)


if __name__ == "__main__":
    main()
