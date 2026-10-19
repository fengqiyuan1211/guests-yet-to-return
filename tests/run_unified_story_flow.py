"""Run story cups, invitation, rewards, restart, reception modes and shop with private saves."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--godot', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
keys = ('slot-wallet', 'dialogue-save', 'game-save', 'menu-save', 'supplies-save',
        'workbench-save', 'customer-save', 'audio-settings')
plans = [('verify_unified_story_flow', [None, '--flow-resume']),
         ('verify_branch_integration', [None, '--integration-resume']),
         ('verify_story_shop_bridge', [None]),
         ('verify_fixed_price_discovery', [None]),
         ('verify_diy_menu', [None, '--research-resume'])]
for scene, passes in plans:
    with tempfile.TemporaryDirectory(prefix='story-flow-', dir='/tmp') as folder:
        for flag in passes:
            command = [args.godot, '--headless', '--path', str(root), '--log-file',
                       str(Path(folder) / 'godot.log'), f'res://tests/{scene}.tscn', '--',
                       '--no-local-services', '--feedback-url=']
            command += [f'--{key}={folder}/{key}.json' for key in keys]
            if flag:
                command.append(flag)
            result = subprocess.run(command, capture_output=True, text=True, timeout=180)
            output = result.stdout + result.stderr
            print(output, flush=True)
            if result.returncode or 'SCRIPT ERROR:' in output:
                raise SystemExit(result.returncode or 1)
print('Story flow, reception and shop checks passed; player saves were not used.')
