from __future__ import annotations

import hmac
import json
import re
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

from .contracts import InputError, STYLE_ID, canonical
from .jobs import ServiceError
from .prompts import PROMPT_VERSION
from .store import StoreError

MAX_BODY = 12 * 1024 * 1024
JOB_PATH = re.compile(r"^/v1/drink-image-jobs/([0-9a-f]{32})(/image|/raw-image)?$")


def make_server(jobs, host=None, port=None):
    settings = jobs.settings

    class Handler(BaseHTTPRequestHandler):
        server_version = "CocktailImage/1"

        def log_message(self, *_args):
            # Prompts/stories, authorization headers and response bodies must
            # not accidentally be copied into terminal logs.
            pass

        def send_bytes(self, status, value, content_type):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(value)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            try:
                self.wfile.write(value)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def send_json(self, status, value):
            self.send_bytes(status, canonical(value).encode("utf-8"), "application/json; charset=utf-8")

        def error(self, status, code, message, field=None):
            value = {"code": code, "message": message}
            if field:
                value["field"] = field
            self.send_json(status, {"error": value})

        def authorized(self):
            token = settings.service_token
            if token and not hmac.compare_digest(self.headers.get("Authorization", "").encode(), ("Bearer " + token).encode()):
                self.error(401, "unauthorized", "服务访问口令不正确。")
                return False
            return True

        def do_GET(self):
            path = urlsplit(self.path).path
            if path == "/":
                self.send_bytes(200, (settings.service_root / "web/index.html").read_bytes(), "text/html; charset=utf-8")
                return
            if path == "/health":
                self.send_json(200, {"status": "ok", "service": "cocktail-image-service", "provider_configured": jobs.configured,
                                     "restart_required": jobs.configuration_changed(),
                                     "model": settings.model, "style_id": STYLE_ID,
                                     "prompt_version": PROMPT_VERSION})
                return
            if not self.authorized():
                return
            match = JOB_PATH.fullmatch(path)
            if not match:
                self.error(404, "not_found", "没有这个接口或任务。")
                return
            row = jobs.store.get(match[1])
            if not row:
                self.error(404, "task_not_found", "没有找到这个任务。")
            elif match[2] == "/raw-image":
                image = settings.data_dir / "jobs" / match[1] / "raw.png"
                if row["status"] not in ("succeeded", "failed") or not image.is_file():
                    self.error(409, "raw_image_not_ready", "这个任务还没有可查看的原始图片。")
                else:
                    self.send_bytes(200, image.read_bytes(), "image/png")
            elif match[2]:
                image = settings.data_dir / "jobs" / match[1] / "image.png"
                if row["status"] != "succeeded" or not image.is_file():
                    self.error(409, "image_not_ready", "这张酒图还未生成成功。")
                else:
                    self.send_bytes(200, image.read_bytes(), "image/png")
            else:
                self.send_json(200, jobs.store.public(row))

        def do_POST(self):
            # The local test page uses the same origin. Godot does not send
            # Origin. Reject cross-site browser requests to the local service.
            origin = self.headers.get("Origin")
            if origin and origin not in ("http://" + self.headers.get("Host", ""), "https://" + self.headers.get("Host", "")):
                self.error(403, "origin_not_allowed", "请从服务自身的测试页面提交。")
                return
            if not self.authorized():
                return
            path = urlsplit(self.path).path
            if path not in ("/v1/drink-image-jobs", "/v1/prompt-preview"):
                self.error(404, "not_found", "没有这个接口。")
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 1 <= length <= MAX_BODY:
                    self.error(413, "invalid_size", "请求为空或超过 12 MiB。")
                    return
                if self.headers.get("Content-Type", "").split(";", 1)[0].lower() != "application/json":
                    self.error(415, "invalid_content_type", "请发送 application/json。")
                    return
                self.connection.settimeout(15)
                body = self.rfile.read(length)
                if len(body) != length:
                    raise ValueError("incomplete")
                def reject_constant(_value):
                    raise ValueError("invalid JSON number")
                data = json.loads(body, parse_constant=reject_constant)
            except (ValueError, UnicodeError, OSError):
                self.error(400, "invalid_json", "请求不是完整有效的 JSON。")
                return
            try:
                value = jobs.preview(data) if path == "/v1/prompt-preview" else jobs.create(data)
                self.send_json(200 if path == "/v1/prompt-preview" else 202, value)
            except InputError as error:
                self.error(400, error.code, error.message, error.field)
            except (StoreError, ServiceError) as error:
                self.error(error.http_status, error.code, error.message)
            except Exception:
                self.error(500, "internal_error", "服务暂时无法处理，请检查配置及可写存储目录。")

    bind_host = host if host is not None else settings.host
    class Server(ThreadingHTTPServer):
        daemon_threads = True
        address_family = socket.AF_INET6 if ":" in bind_host else socket.AF_INET
    return Server((bind_host, settings.port if port is None else port), Handler)
