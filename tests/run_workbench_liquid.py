"""Run liquid regression checks with private saves; never touch the player profile.

python3 tests/run_workbench_liquid.py --godot /path/to/Godot --graphics
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SAVE_KEYS = ('slot-wallet', 'dialogue-save', 'game-save', 'menu-save',
             'supplies-save', 'workbench-save', 'audio-settings')


def run(godot, scene, saves, *, graphics=False, resume=False):
    command = [godot]
    if not graphics:
        command.append('--headless')
    command += ['--path', str(ROOT), f'tests/{scene}.tscn', '--']
    command += [f'--{key}={saves / (key + ".json")}' for key in SAVE_KEYS]
    if resume:
        command.append('--liquid-resume')
    print(f'Running {scene}' + (' (new-process restore)' if resume else ''), flush=True)
    completed = subprocess.run(command, timeout=60, check=False)
    if completed.returncode:
        raise SystemExit(completed.returncode)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, help='Godot 4 executable')
    parser.add_argument('--graphics', action='store_true', help='Include native UI and restart checks')
    args = parser.parse_args()
    for scene in ('verify_workbench_liquid', 'verify_workbench_evaluation',
                  'verify_workbench_inventory', 'verify_workbench_finishing'):
        with tempfile.TemporaryDirectory(prefix='liquid-check-', dir='/tmp') as folder:
            run(args.godot, scene, Path(folder))
    if args.graphics:
        with tempfile.TemporaryDirectory(prefix='liquid-visual-', dir='/tmp') as folder:
            run(args.godot, 'verify_workbench_liquid_visual', Path(folder), graphics=True)
            run(args.godot, 'verify_workbench_liquid_visual', Path(folder), resume=True)
    print('Liquid regression checks passed.')


if __name__ == '__main__':
    main()
