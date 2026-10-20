#!/bin/sh
# GODOT_BIN can point to a custom installation on any platform with a POSIX shell.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
godot_bin=${GODOT_BIN:-}
if [ -z "$godot_bin" ]; then
  for candidate in /Applications/Godot.app/Contents/MacOS/Godot "$HOME/Applications/Godot.app/Contents/MacOS/Godot" "$HOME/Downloads/Godot.app/Contents/MacOS/Godot"; do
    if [ -x "$candidate" ]; then godot_bin=$candidate; break; fi
  done
fi
if [ -z "$godot_bin" ]; then godot_bin=$(command -v godot || command -v godot4 || true); fi
if [ -z "$godot_bin" ] || [ ! -x "$godot_bin" ]; then
  echo '找不到 Godot。请用 Godot 导入 project.godot，或设置 GODOT_BIN 为程序路径。' >&2
  exit 1
fi
if [ ! -d "$project_dir/.godot/imported" ]; then
  echo '首次启动，正在导入游戏素材……'
  "$godot_bin" --headless --editor --path "$project_dir" --import
fi
exec "$godot_bin" --path "$project_dir" "$@"
