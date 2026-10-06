#!/bin/zsh
cd "$(dirname "$0")" || exit 1
if [[ -x ".venv/bin/python" ]]; then
  image_python=".venv/bin/python"
elif [[ -x "$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3" ]]; then
  image_python="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
else
  image_python="python3"
fi
if ! "$image_python" -c 'from PIL import Image' >/dev/null 2>&1; then
  print "请先按本目录 README.md 的说明安装 Python 和 requirements.txt，然后重新打开。"
  read "?按回车退出"
  exit 1
fi
exec "$image_python" run.py
