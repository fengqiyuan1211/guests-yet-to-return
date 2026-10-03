"""Qwen's synchronous, OpenAI-compatible image generation transport.

Reference: https://help.aliyun.com/zh/model-studio/qwen-image-generation-and-editing-api-reference
Generation is submitted once. Temporary output URLs are downloaded immediately;
no provider URL or response body is returned as a permanent image artifact.
"""

from __future__ import annotations

import base64
import binascii
from dataclasses import dataclass
from http.client import HTTPException
from io import BytesIO
import json
import math
import re
import socket
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
import warnings

from PIL import Image, UnidentifiedImageError


MAX_JSON_BYTES = 1024 * 1024
MAX_ERROR_BYTES = 64 * 1024
MAX_IMAGE_BYTES = 20 * 1024 * 1024
MAX_IMAGE_PIXELS = 16 * 1024 * 1024


class _NoRedirects(HTTPRedirectHandler):
    """Avoid replaying generation or forwarding its bearer token on redirects."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


# Kept at module scope so tests can replace transport without calling a paid API.
urlopen = build_opener(_NoRedirects()).open


class ProviderError(Exception):
    """A stable, safe-to-display provider failure, without remote body text."""

    def __init__(self, code: str, message: str, retryable: bool = False, *,
                 http_status: int | None = None, remote_code: str | None = None,
                 request_id: str | None = None):
        self.code = code
        self.message = message
        self.retryable = retryable
        self.http_status = http_status
        self.remote_code = remote_code
        self.request_id = request_id
        super().__init__(message)


@dataclass(frozen=True)
class ProviderResult:
    image_bytes: bytes
    request_id: str | None
    model: str
    usage: dict


def _bounded_read(response, limit: int, oversized_code: str, invalid_code: str) -> bytes:
    length = response.headers.get("Content-Length")
    expected = None
    if length is not None:
        try:
            expected = int(length)
        except (ValueError, TypeError):
            raise ProviderError(invalid_code, "The upstream response has an invalid content length.") from None
        if expected < 0:
            raise ProviderError(invalid_code, "The upstream response has an invalid content length.")
        if expected > limit:
            raise ProviderError(oversized_code, "The upstream response exceeds the allowed size.")
    chunks = []
    total = 0
    while True:
        chunk = response.read(min(64 * 1024, limit - total + 1))
        if not chunk:
            break
        total += len(chunk)
        if total > limit:
            raise ProviderError(oversized_code, "The upstream response exceeds the allowed size.")
        chunks.append(chunk)
    if expected is not None and total != expected:
        raise ProviderError(invalid_code, "The upstream response was incomplete.", retryable=True)
    return b"".join(chunks)


def _request_id(headers) -> str | None:
    value = headers.get("x-request-id")
    if not isinstance(value, str):
        return None
    value = value.strip()
    if not value or len(value) > 200 or not all(c.isalnum() or c in "-_.:" for c in value):
        return None
    return value


def _http_failure(error: HTTPError, api_key: str) -> ProviderError:
    """Keep bounded diagnostic identifiers, never the upstream message or body."""
    status = error.code if type(error.code) is int and 100 <= error.code <= 599 else None
    headers = error.headers or {}
    response_id = _request_id(headers)
    if response_id and api_key.casefold() in response_id.casefold():
        response_id = None
    remote_code = None
    mime = headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
    try:
        if not mime or mime == "application/json" or mime.endswith("+json"):
            # Read at most 64 KiB once, including on declared or actual oversized errors.
            data = json.loads(error.read(MAX_ERROR_BYTES))
            if isinstance(data, dict):
                nested = data.get("error")
                nested = nested if isinstance(nested, dict) else {}
                candidates = (nested.get("code"), data.get("code"), nested.get("type"), data.get("type"))
                for value in candidates:
                    if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:-]{0,99}", value) \
                            and api_key.casefold() not in value.casefold():
                        remote_code = value
                        break
    except (OSError, ValueError, HTTPException, RecursionError):
        pass
    finally:
        try:
            error.close()
        except OSError:
            pass
    if status == 401:
        message = "绘图服务的 API Key 无效或已过期，请更新后重启服务。"
    elif status == 403:
        message = "当前 API Key 无权使用该模型或工作空间，请检查授权和地域。"
    elif status == 404:
        if remote_code and remote_code.lower().replace("_", "").replace("-", "") == "modelnotfound":
            message = "未找到指定的绘图模型，请检查模型名、地域和工作空间。"
        else:
            message = "未找到绘图接口，请检查服务地址、地域和工作空间，并重启服务。"
    elif status == 429:
        message = "绘图服务限流，请稍后手动重试。"
    elif status is not None and 500 <= status <= 599:
        message = "绘图服务暂时不可用，请稍后手动重试。"
    else:
        message = "绘图服务请求失败，请检查接口配置。" if status is None \
            else f"绘图服务返回 HTTP {status}，请检查接口配置。"
    return ProviderError("provider_http_error", message,
                         retryable=status == 429 or (status is not None and 500 <= status <= 599),
                         http_status=status, remote_code=remote_code, request_id=response_id)


def _valid_png(data: bytes) -> bool:
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        return False
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(data)) as image:
                if image.format != "PNG" or image.width * image.height > MAX_IMAGE_PIXELS:
                    return False
                if getattr(image, "is_animated", False):
                    return False
                image.verify()
            with Image.open(BytesIO(data)) as image:
                image.load()
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError, EOFError, Image.DecompressionBombError,
            Image.DecompressionBombWarning):
        return False
    return True


class QwenImageProvider:
    def __init__(self, settings):
        self.settings = settings

    def _configuration(self) -> tuple[str, str, str, float]:
        key = getattr(self.settings, "api_key", None)
        base_url = getattr(self.settings, "base_url", None)
        model = getattr(self.settings, "model", None)
        timeout = getattr(self.settings, "timeout", None)
        output_size = getattr(self.settings, "output_size", 1024)
        if not isinstance(key, str) or not key.strip() or "\r" in key or "\n" in key:
            raise ProviderError("invalid_configuration", "A valid provider API key is required.")
        if not isinstance(base_url, str) or not isinstance(model, str) or not model.strip():
            raise ProviderError("invalid_configuration", "A provider endpoint and model are required.")
        try:
            parsed = urlsplit(base_url)
            valid_endpoint = (parsed.scheme in ("https", "http") and parsed.hostname
                              and not parsed.username and not parsed.password
                              and not parsed.query and not parsed.fragment)
        except ValueError:
            valid_endpoint = False
        if not valid_endpoint:
            raise ProviderError("invalid_configuration", "The provider endpoint is invalid.")
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or timeout <= 0:
            raise ProviderError("invalid_configuration", "The provider timeout must be a positive number.")
        if output_size not in (1024, "1024x1024"):
            raise ProviderError("invalid_configuration", "This image service requires a 1024x1024 generation size.")
        return key.strip(), base_url.rstrip("/"), model.strip(), float(timeout)

    def generate(self, prompt: str, images: list[str], seed: int) -> ProviderResult:
        key, base_url, model, timeout = self._configuration()
        if not isinstance(prompt, str) or not prompt.strip():
            raise ProviderError("invalid_input", "A nonempty image prompt is required.")
        if not isinstance(images, list) or len(images) > 3:
            raise ProviderError("invalid_input", "Provide zero to three image data URLs.")
        for image in images:
            if not isinstance(image, str) or not image.startswith("data:image/") or ";base64," not in image:
                raise ProviderError("invalid_input", "Reference images must be image data URLs.")
            encoded = image.split(";base64,", 1)[1]
            if len(encoded) > ((MAX_IMAGE_BYTES + 2) // 3) * 4:
                raise ProviderError("invalid_input", "A reference image exceeds the allowed size.")
            try:
                decoded = base64.b64decode(encoded, validate=True)
            except (ValueError, binascii.Error):
                raise ProviderError("invalid_input", "A reference image contains invalid base64 data.") from None
            if not decoded or len(decoded) > MAX_IMAGE_BYTES:
                raise ProviderError("invalid_input", "A reference image is empty or exceeds the allowed size.")
        if isinstance(seed, bool) or not isinstance(seed, int) or not 0 <= seed <= 2_147_483_647:
            raise ProviderError("invalid_input", "The image seed must be an integer between 0 and 2147483647.")
        payload = {"model": model, "prompt": prompt, "size": "1024x1024", "n": 1,
                   "prompt_extend": False, "watermark": False, "seed": seed}
        if images:
            payload["image"] = images
        request = Request(base_url + "/images/generations",
                          data=json.dumps(payload, ensure_ascii=False, allow_nan=False).encode("utf-8"),
                          headers={"Authorization": "Bearer " + key, "Content-Type": "application/json",
                                   "Accept": "application/json"}, method="POST")
        try:
            with urlopen(request, timeout=timeout) as response:
                response_id = _request_id(response.headers)
                body = _bounded_read(response, MAX_JSON_BYTES,
                                     "invalid_provider_response", "invalid_provider_response")
        except HTTPError as error:
            raise _http_failure(error, key) from None
        except (socket.timeout, TimeoutError):
            raise ProviderError("provider_timeout", "The image provider timed out; generation was not retried.", True) from None
        except URLError as error:
            if isinstance(error.reason, (socket.timeout, TimeoutError)):
                raise ProviderError("provider_timeout", "The image provider timed out; generation was not retried.", True) from None
            raise ProviderError("provider_network_error", "The image provider could not be reached; generation was not retried.", True) from None
        except (OSError, ValueError, HTTPException):
            raise ProviderError("provider_network_error", "The image provider request could not be completed; generation was not retried.", True) from None
        try:
            result = json.loads(body)
            image_url = result["data"][0]["url"]
        except (ValueError, TypeError, KeyError, IndexError):
            raise ProviderError("invalid_provider_response", "The image provider did not return a usable image URL.") from None
        if not isinstance(image_url, str):
            raise ProviderError("invalid_provider_response", "The image provider returned an invalid image URL.")
        try:
            parsed = urlsplit(image_url)
            valid_url = parsed.scheme in ("https", "http") and parsed.hostname and not parsed.username and not parsed.password
        except ValueError:
            valid_url = False
        if not valid_url:
            raise ProviderError("invalid_provider_response", "The image provider returned an invalid image URL.")
        usage = result.get("usage", {})
        if not isinstance(usage, dict):
            raise ProviderError("invalid_provider_response", "The image provider returned invalid usage metadata.")
        image_request = Request(image_url, headers={"Accept": "image/png"}, method="GET")
        try:
            with urlopen(image_request, timeout=timeout) as response:
                content_type = response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
                if content_type and content_type not in ("image/png", "application/octet-stream"):
                    raise ProviderError("invalid_image", "The generated image download is not a PNG response.")
                image_bytes = _bounded_read(response, MAX_IMAGE_BYTES,
                                            "image_too_large", "image_download_failed")
        except (HTTPError, URLError, socket.timeout, TimeoutError, OSError, ValueError, HTTPException):
            raise ProviderError("image_download_failed", "The generated image could not be downloaded; generation was not retried.", True) from None
        if not _valid_png(image_bytes):
            raise ProviderError("invalid_image", "The generated image download is not a valid static PNG.")
        return ProviderResult(image_bytes=image_bytes, request_id=response_id, model=model, usage=usage)
