#!/bin/zsh
# Open the main game to chat, select a drink, then enter the workbench.
project_dir="${0:A:h}"
godot_bin="/Users/wit/Downloads/Godot.app/Contents/MacOS/Godot"
if [[ ! -x "$godot_bin" ]]; then
  print "找不到 Godot，请检查：$godot_bin"
  read "?按回车关闭"
  exit 1
fi
exec "$godot_bin" --path "$project_dir"
