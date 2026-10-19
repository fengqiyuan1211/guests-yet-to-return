"""Start local game backends without model requests, secret arguments or a console."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import time
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import ProxyHandler, Request, build_opener


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    temporary.replace(path)


def health(origin: str, kind: str) -> dict | None:
    try:
        request = Request(origin.rstrip("/") + "/health")
        with build_opener(ProxyHandler({})).open(request, timeout=2.0) as response:
            if response.status != 200:
                return None
            value = json.loads(response.read(8192))
        if kind == "image" and value.get("status") == "ok" and "provider_configured" in value:
            return value
        if kind == "feedback" and value.get("ok") is True and value.get("max_rounds") == 3:
            return value
    except HTTPError as error:
        try:
            value = json.loads(error.read(8192))
            if kind == "image" and error.code == 503 and value.get("service") == "cocktail-image-service":
                return value
        except (OSError, ValueError):
            pass
    except (OSError, ValueError):
        pass
    return None


def occupied(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=0.4):
            return True
    except OSError:
        return False


def python_for(directory: Path, kind: str) -> str | None:
    candidates = [directory / ".venv/bin/python", directory / ".venv/Scripts/python.exe", sys.executable]
    bundled = Path.home() / ".cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
    candidates.extend([bundled, shutil.which("python3"), shutil.which("python")])
    probe = "import sys; assert sys.version_info >= (3, 10)"
    if kind == "image":
        probe += "; from PIL import Image"
    for candidate in dict.fromkeys(str(p) for p in candidates if p):
        try:
            result = subprocess.run([candidate, "-c", probe], stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL, timeout=3,
                                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            if result.returncode == 0:
                return candidate
        except (OSError, subprocess.TimeoutExpired):
            continue
    return None


def ready_report(value: dict, kind: str, reused: bool, pid: int | None = None) -> dict:
    if value.get("status") == "unavailable":
        return {"status": "error", "message": "酒图服务无法访问本地配置或记录，请重启酒图服务后重试。"}
    if value.get("restart_required"):
        return {"status": "error", "message": "酒图配置已更新，请重启酒图服务后重试。"}
    return {"status": "ready", "configured": bool(value.get("provider_configured" if kind == "image" else "configured")),
            "reused": reused, "pid": pid, "message": ""}


def ensure_service(project: Path, state: Path, kind: str, url: str) -> dict:
    if not url:
        return {"status": "disabled", "message": "服务已关闭。"}
    parsed = urlsplit(url)
    if parsed.hostname not in ("127.0.0.1", "localhost", "::1") or parsed.scheme != "http":
        return {"status": "remote", "message": "使用已配置的远程服务。"}
    port = parsed.port or 80
    host = parsed.hostname
    origin = f"http://[{host}]:{port}" if host == "::1" else f"http://{host}:{port}"
    value = health(origin, kind)
    if value is not None:
        return ready_report(value, kind, True)
    if occupied(host, port):
        return {"status": "error", "message": "服务端口被其他程序占用，请检查本机配置。"}
    lock = state / f"launch-{kind}-{port}.lock"
    state.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + 25
    while True:
        try:
            descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            os.write(descriptor, str(os.getpid()).encode())
            os.close(descriptor)
            break
        except FileExistsError:
            value = health(origin, kind)
            if value is not None:
                return ready_report(value, kind, True)
            if time.monotonic() >= deadline:
                return {"status": "error", "message": "服务启动等待超时，请重新打开游戏。"}
            try:
                stale = time.time() - lock.stat().st_mtime > 60
                if stale:
                    lock.unlink(missing_ok=True)
            except OSError:
                pass
            time.sleep(0.2)
    try:
        value = health(origin, kind)
        if value is not None:
            return ready_report(value, kind, True)
        directory = project / "services" / ("cocktail-image-service" if kind == "image" else "customer-feedback-service")
        entry = directory / "run.py"
        if not entry.is_file():
            return {"status": "error", "message": "缺少服务文件，请同步完整的 services 文件夹。"}
        interpreter = python_for(directory, kind)
        if interpreter is None:
            return {"status": "error", "message": "请安装 Python 3.10 及以上版本" + ("和 Pillow。" if kind == "image" else "。")}
        env = os.environ.copy()
        if kind == "image":
            env["IMAGE_SERVICE_HOST"] = host
            env["IMAGE_SERVICE_PORT"] = str(port)
        else:
            env["FEEDBACK_PORT"] = str(port)
        log = state / f"{kind}.log"
        with log.open("ab") as output:
            process = subprocess.Popen([interpreter, "-u", str(entry)], cwd=directory,
                                       env=env, stdin=subprocess.DEVNULL, stdout=output, stderr=output,
                                       start_new_session=os.name != "nt",
                                       creationflags=(subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP)
                                       if os.name == "nt" else 0)
        while time.monotonic() < deadline:
            value = health(origin, kind)
            if value is not None:
                return ready_report(value, kind, False, process.pid)
            if process.poll() is not None:
                return {"status": "error", "message": "服务启动失败，请检查服务配置或依赖。"}
            time.sleep(0.2)
        return {"status": "error", "pid": process.pid, "message": "服务仍未就绪，请稍后重试。"}
    finally:
        lock.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", type=Path, required=True)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--image-url", default="http://127.0.0.1:8787")
    parser.add_argument("--feedback-url", default="http://127.0.0.1:8788/feedback")
    args = parser.parse_args()
    result = {"image": {"status": "starting"}, "feedback": {"status": "starting"}}
    atomic_json(args.report, result)
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = {kind: executor.submit(ensure_service, args.project_dir, args.state_dir, kind, url)
                   for kind, url in [("image", args.image_url), ("feedback", args.feedback_url)]}
        pending = dict(futures)
        while pending:
            for kind, future in list(pending.items()):
                if not future.done():
                    continue
                try:
                    result[kind] = future.result()
                except Exception:
                    result[kind] = {"status": "error", "message": "服务启动检查失败，请检查本机配置。"}
                atomic_json(args.report, result)
                del pending[kind]
            if pending:
                time.sleep(0.1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
