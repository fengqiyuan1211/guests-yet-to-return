from __future__ import annotations

import base64
import hashlib
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from .contracts import Request, canonical, parse_request
from .imaging import ProcessingError, normalize_image
from .prompts import PROMPT_VERSION, PromptBuilder
from .provider import ProviderError, QwenImageProvider
from .store import JobStore, StoreError


class ServiceError(Exception):
    def __init__(self, code, message, http_status=503):
        super().__init__(message)
        self.code, self.message, self.http_status = code, message, http_status


def atomic_write(path: Path, value: bytes):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(value)
    temporary.replace(path)


class ImageJobs:
    def __init__(self, settings, provider=None):
        self.settings = settings
        self.builder = PromptBuilder(settings.service_root, settings.reference_images)
        self.store = JobStore(settings.data_dir, settings.max_pending)
        self.store.recover_interrupted()
        self.provider = provider if provider is not None else QwenImageProvider(settings)
        self.configured = bool(settings.api_key) or provider is not None
        self.env_stamp = self._config_stamp()
        self.executor = ThreadPoolExecutor(max_workers=settings.workers, thread_name_prefix="cocktail-image")
        self._lock = threading.Lock()
        self._closed = False

    def _config_stamp(self):
        try:
            value = (self.settings.service_root / ".env").stat()
            return value.st_mtime_ns, value.st_size
        except FileNotFoundError:
            return None

    def configuration_changed(self):
        return self._config_stamp() != self.env_stamp

    def parse(self, data):
        return parse_request(data, self.builder.profiles)

    def preview(self, data):
        request = self.parse(data)
        bundle = self.builder.build(request)
        return {"recipe": request.recipe, "recipe_hash": request.recipe_hash,
                "request_hash": request.request_hash, "prompt": bundle.prompt,
                "metadata": bundle.metadata, "paid_request": False}

    def create(self, data):
        request = self.parse(data)
        with self._lock:
            if self._closed:
                raise ServiceError("service_stopping", "服务正在关闭，请稍后再试。")
            with self.store.connect() as connection:
                previous = connection.execute("SELECT * FROM jobs WHERE request_id=?", (request.request_id,)).fetchone()
            if previous:
                if previous["request_hash"] != request.request_hash:
                    raise StoreError("request_id_conflict", "request_id 已绑定另一份配方、故事或预览图，请使用新 ID。", 409)
                return self.store.public(dict(previous))
            if self.configuration_changed():
                raise ServiceError("configuration_changed", "配置已修改，请先重启出图服务，再点击生成酒图。")
            if not self.configured:
                raise ServiceError("provider_not_configured", "请先在服务的 .env 中填写 DASHSCOPE_API_KEY，再重启服务。")
            bundle = self.builder.build(request)
            row, created = self.store.create(request)
            if created:
                try:
                    self.executor.submit(self._run, row["task_id"], request, bundle)
                except RuntimeError:
                    self.store.update(row["task_id"], "failed", error={"code": "service_stopping", "message": "服务关闭时任务未启动，请手动再试。", "retryable": True})
            # Return the committed initial state; polling delivers later states.
            return self.store.public(row)

    def _run(self, task_id, request: Request, bundle):
        directory = self.settings.data_dir / "jobs" / task_id
        record = {"schema_version": 1, "task_id": task_id, "request_id": request.request_id,
                  "recipe": request.recipe, "recipe_hash": request.recipe_hash,
                  "request_hash": request.request_hash, "metadata": bundle.metadata,
                  "provider": {"model": self.settings.model, "size": "1024x1024", "n": 1,
                               "prompt_extend": False, "watermark": False, "seed": bundle.seed},
                  "status": "running"}
        try:
            directory.mkdir(parents=True, exist_ok=True)
            self.store.update(task_id, "running")
            atomic_write(directory / "prompt.txt", bundle.prompt.encode("utf-8"))
            if request.preview_image:
                preview = base64.b64decode(request.preview_image.split(",", 1)[1])
                atomic_write(directory / "rule-preview.png", preview)
                record["preview_sha256"] = hashlib.sha256(preview).hexdigest()
            atomic_write(directory / "record.json", canonical(record).encode("utf-8"))
            # Deliberately exactly one upstream generation attempt. A timeout
            # may still have consumed credit; resubmission must be explicit.
            output = self.provider.generate(bundle.prompt, bundle.images, bundle.seed)
            atomic_write(directory / "raw.png", output.image_bytes)
            record["provider"].update({"model": output.model, "request_id": output.request_id, "usage": output.usage})
            normalized, processing = normalize_image(output.image_bytes, self.settings.output_size)
            atomic_write(directory / "image.png", normalized)
            result = {"image_url": f"/v1/drink-image-jobs/{task_id}/image",
                      "width": self.settings.output_size, "height": self.settings.output_size,
                      "mime_type": "image/png", "transparent": processing["alpha"],
                      "needs_review": True, "semantic_validation": "not_performed",
                      "style_id": request.style_id, "prompt_version": PROMPT_VERSION,
                      "recipe_hash": request.recipe_hash,
                      "image_sha256": hashlib.sha256(normalized).hexdigest(),
                      "few_shot_ids": bundle.metadata["few_shot_ids"],
                      "processing": processing}
            record.update({"status": "succeeded", "result": result})
            atomic_write(directory / "record.json", canonical(record).encode("utf-8"))
            self.store.update(task_id, "succeeded", result=result)
        except (ProviderError, ProcessingError) as error:
            safe = {"code": error.code, "message": error.message, "retryable": getattr(error, "retryable", False)}
            for field in ("http_status", "remote_code", "request_id"):
                value = getattr(error, field, None)
                if value is not None:
                    safe[field] = value
            self._fail(task_id, directory, record, safe)
        except Exception:
            # Do not surface untrusted upstream bodies, local paths or secrets.
            self._fail(task_id, directory, record, {"code": "processing_failed", "message": "出图或保存未能完成，请检查服务运行目录是否可写。", "retryable": False})

    def _fail(self, task_id, directory, record, safe):
        record.update({"status": "failed", "error": safe})
        try:
            atomic_write(directory / "record.json", canonical(record).encode("utf-8"))
        except OSError:
            pass
        self.store.update(task_id, "failed", error=safe)

    def close(self):
        with self._lock:
            self._closed = True
        self.executor.shutdown(wait=True, cancel_futures=False)
