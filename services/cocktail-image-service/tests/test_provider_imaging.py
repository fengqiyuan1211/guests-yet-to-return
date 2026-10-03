"""Offline checks for provider requests and conservative image processing."""

from __future__ import annotations

import base64
from http.client import IncompleteRead
from io import BytesIO
import json
import socket
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError
from urllib.request import Request

from PIL import Image, ImageDraw

from cocktail_service.imaging import ProcessingError, normalize_image
from cocktail_service.provider import ProviderError, QwenImageProvider


MAX_JSON_BYTES = 1024 * 1024
MAX_IMAGE_BYTES = 20 * 1024 * 1024
MAX_ERROR_BYTES = 64 * 1024
API_KEY = "test-api-key-never-log-this"
DOWNLOAD_URL = "https://images.example.test/generated.png"


def image_bytes(image: Image.Image, format: str = "PNG") -> bytes:
    output = BytesIO()
    image.save(output, format=format)
    return output.getvalue()


def png_fixture() -> bytes:
    image = Image.new("RGBA", (24, 32), (0, 0, 0, 0))
    ImageDraw.Draw(image).rectangle((6, 5, 17, 26), fill=(170, 92, 30, 255))
    return image_bytes(image)


def data_url() -> str:
    return "data:image/png;base64," + base64.b64encode(png_fixture()).decode("ascii")


class FakeResponse:
    """A response with real bounded reads and the urllib response protocol."""

    def __init__(self, body: bytes, *, headers: dict[str, str] | None = None):
        self.body = BytesIO(body)
        self.headers = headers or {}
        self.status = 200
        self.read_sizes: list[int] = []

    def read(self, size: int = -1) -> bytes:
        self.read_sizes.append(size)
        return self.body.read(size)

    def getcode(self) -> int:
        return self.status

    def getheader(self, name: str, default: str | None = None) -> str | None:
        return self.headers.get(name, default)

    def close(self) -> None:
        pass

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()


def provider_response(**overrides: object) -> FakeResponse:
    body: dict[str, object] = {
        "data": [{"url": DOWNLOAD_URL}],
        "request_id": "provider-request-123",
        "model": "qwen-image-3.0-pro",
        "usage": {"image_count": 1},
    }
    body.update(overrides)
    return FakeResponse(
        json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "x-request-id": "provider-request-123"},
    )


def settings(**overrides: object) -> SimpleNamespace:
    values = {
        "api_key": API_KEY,
        "base_url": "https://provider.example.test/v1",
        "model": "qwen-image-3.0-pro",
        "timeout": 30,
        "output_size": 1024,
    }
    values.update(overrides)
    return SimpleNamespace(**values)


def request_headers(request: Request) -> dict[str, str]:
    return {name.lower(): value for name, value in request.header_items()}


class ErrorBody(BytesIO):
    def __init__(self, value: bytes):
        super().__init__(value)
        self.read_sizes = []
        self.bytes_read = 0

    def read(self, size=-1):
        self.read_sizes.append(size)
        value = super().read(size)
        self.bytes_read += len(value)
        return value


class ProviderTests(unittest.TestCase):
    def setUp(self) -> None:
        self.provider = QwenImageProvider(settings())

    def assert_failure(self, error: ProviderError, code: str) -> None:
        self.assertEqual(error.code, code)
        self.assertIsInstance(error.message, str)
        self.assertTrue(error.message)
        self.assertNotIn(API_KEY, error.message)
        self.assertNotIn(API_KEY, str(error))

    def test_generation_parameters_and_download_auth_boundary(self) -> None:
        generated_png = png_fixture()
        with patch(
            "cocktail_service.provider.urlopen",
            side_effect=[provider_response(), FakeResponse(generated_png)],
        ) as mocked:
            result = self.provider.generate("One cocktail in a clear glass", [], 17)

        self.assertEqual(result.image_bytes, generated_png)
        self.assertEqual(result.model, "qwen-image-3.0-pro")
        self.assertEqual(mocked.call_count, 2)
        post = mocked.call_args_list[0].args[0]
        self.assertIsInstance(post, Request)
        self.assertEqual(post.full_url, "https://provider.example.test/v1/images/generations")
        self.assertEqual(post.get_method(), "POST")
        self.assertEqual(request_headers(post)["authorization"], "Bearer " + API_KEY)
        self.assertIn("application/json", request_headers(post)["content-type"])
        payload = json.loads(post.data)
        self.assertEqual(payload["model"], "qwen-image-3.0-pro")
        self.assertEqual(payload["prompt"], "One cocktail in a clear glass")
        self.assertEqual(payload["seed"], 17)
        self.assertEqual(payload["size"], "1024x1024")
        self.assertEqual(payload["n"], 1)
        self.assertIs(payload["prompt_extend"], False)
        self.assertIs(payload["watermark"], False)
        self.assertNotIn("image", payload)

        download = mocked.call_args_list[1].args[0]
        if isinstance(download, Request):
            self.assertEqual(download.full_url, DOWNLOAD_URL)
            self.assertEqual(download.get_method(), "GET")
            self.assertNotIn("authorization", request_headers(download))
        else:
            self.assertEqual(download, DOWNLOAD_URL)

    def test_one_and_three_reference_images_are_sent_as_image_list(self) -> None:
        reference = data_url()
        for count in (1, 3):
            with self.subTest(count=count):
                references = [reference] * count
                with patch(
                    "cocktail_service.provider.urlopen",
                    side_effect=[provider_response(), FakeResponse(png_fixture())],
                ) as mocked:
                    self.provider.generate("Recipe preview", references, 23)
                payload = json.loads(mocked.call_args_list[0].args[0].data)
                self.assertEqual(payload["image"], references)

    def test_square_output_size_can_be_configured_as_string(self) -> None:
        provider = QwenImageProvider(settings(output_size="1024x1024"))
        with patch(
            "cocktail_service.provider.urlopen",
            side_effect=[provider_response(), FakeResponse(png_fixture())],
        ) as mocked:
            provider.generate("Recipe preview", [], 24)
        self.assertEqual(json.loads(mocked.call_args_list[0].args[0].data)["size"], "1024x1024")

    def test_invalid_references_fail_before_network_access(self) -> None:
        invalid_inputs = [
            [data_url()] * 4,
            ["https://example.test/reference.png"],
            ["data:image/png;base64,this-is-not-base64!"],
        ]
        for references in invalid_inputs:
            with self.subTest(references=references):
                with patch("cocktail_service.provider.urlopen") as mocked:
                    with self.assertRaises(ProviderError) as caught:
                        self.provider.generate("Recipe preview", references, 25)
                self.assert_failure(caught.exception, "invalid_input")
                mocked.assert_not_called()

    def test_missing_api_key_fails_before_network_access(self) -> None:
        with patch("cocktail_service.provider.urlopen") as mocked:
            with self.assertRaises(ProviderError) as caught:
                QwenImageProvider(settings(api_key="")).generate("Recipe preview", [], 26)
        self.assert_failure(caught.exception, "invalid_configuration")
        mocked.assert_not_called()

    def test_http_error_is_redacted_and_is_not_retried(self) -> None:
        raw_body = "private-provider-body " + API_KEY
        failure = HTTPError(
            "https://provider.example.test/v1/images/generations",
            429,
            "Too Many Requests",
            {},
            BytesIO(raw_body.encode("utf-8")),
        )
        with patch("cocktail_service.provider.urlopen", side_effect=failure) as mocked:
            with self.assertRaises(ProviderError) as caught:
                self.provider.generate("Recipe preview", [], 27)
        self.assert_failure(caught.exception, "provider_http_error")
        self.assertNotIn("private-provider-body", caught.exception.message)
        self.assertEqual(mocked.call_count, 1)

    def http_failure(self, status=404, body=None, *, headers=None):
        if body is None:
            body = {"error": {"message": "private-message " + API_KEY}}
        raw = json.dumps(body).encode("utf-8") if not isinstance(body, bytes) else body
        stream = ErrorBody(raw)
        failure = HTTPError(
            "https://provider.example.test/v1/images/generations", status,
            "private-reason " + API_KEY,
            {"Content-Type": "application/json", "x-request-id": "req-offline-42", **(headers or {})}, stream,
        )
        with patch("cocktail_service.provider.urlopen", side_effect=failure) as mocked:
            with self.assertRaises(ProviderError) as caught:
                self.provider.generate("Recipe preview", [], 27)
        error = caught.exception
        self.assert_failure(error, "provider_http_error")
        self.assertEqual(mocked.call_count, 1)
        self.assertNotIn(API_KEY, json.dumps(vars(error)))
        self.assertNotIn("private-message", json.dumps(vars(error)))
        self.assertNotIn("private-reason", str(error))
        self.assertFalse(hasattr(error, "body"))
        return error, stream

    def test_provider_error_original_signature_keeps_optional_diagnostics_empty(self):
        error = ProviderError("old_code", "旧提示", True)
        self.assertEqual((error.code, error.message, error.retryable), ("old_code", "旧提示", True))
        self.assertIsNone(error.http_status)
        self.assertIsNone(error.remote_code)
        self.assertIsNone(error.request_id)

    def test_http_error_extracts_supported_structured_code_formats(self):
        for body, expected in (
            ({"error": {"code": "model_not_found", "message": API_KEY}}, "model_not_found"),
            ({"code": "ModelNotFound", "message": API_KEY}, "ModelNotFound"),
            ({"type": "invalid_request_error", "message": API_KEY}, "invalid_request_error"),
            ({"error": {"type": "invalid_request_error", "message": API_KEY}}, "invalid_request_error"),
        ):
            with self.subTest(expected=expected):
                error, _ = self.http_failure(body=body)
                self.assertEqual(error.http_status, 404)
                self.assertEqual(error.remote_code, expected)
                self.assertEqual(error.request_id, "req-offline-42")
        error, _ = self.http_failure(body={"code": "InvalidParameter"}, headers={"Content-Type": "application/problem+json"})
        self.assertEqual(error.remote_code, "InvalidParameter")

    def test_http_error_fixed_chinese_messages_distinguish_model_and_route_404(self):
        for status, code, hint, retryable in (
            (401, "InvalidApiKey", "更新后重启", False),
            (403, "AccessDenied", "授权", False),
            (404, "model_not_found", "绘图模型", False),
            (404, "ModelNotFound", "绘图模型", False),
            (404, "RouteNotFound", "绘图接口", False),
            (429, "RateLimitExceeded", "限流", True),
            (500, "InternalError", "暂时不可用", True),
            (503, "ServiceUnavailable", "暂时不可用", True),
        ):
            with self.subTest(status=status, code=code):
                error, _ = self.http_failure(status, {"error": {"code": code, "message": API_KEY}})
                self.assertEqual(error.http_status, status)
                self.assertEqual(error.remote_code, code)
                self.assertIn(hint, error.message)
                self.assertIs(error.retryable, retryable)

    def test_non_json_errors_keep_status_and_request_id_without_body_text(self):
        for body, mime in (
            (b"<html>private-message " + API_KEY.encode() + b"</html>", "text/html"),
            (b"not JSON " + API_KEY.encode(), "application/json"),
            (b"[]", "application/json"),
        ):
            with self.subTest(mime=mime, body=body[:12]):
                error, stream = self.http_failure(body=body, headers={"Content-Type": mime})
                self.assertEqual(error.http_status, 404)
                self.assertEqual(error.request_id, "req-offline-42")
                self.assertIsNone(error.remote_code)
                self.assertIn("绘图接口", error.message)
                if mime == "text/html":
                    self.assertEqual(stream.bytes_read, 0)

    def test_unsafe_or_secret_structured_codes_are_discarded(self):
        for code in (API_KEY, API_KEY.upper(), "prefix:" + API_KEY, "evil\ncode", "<script>",
                     "x" * 101, "中文错误", {"code": "nested"}, 123):
            with self.subTest(code=code):
                error, _ = self.http_failure(body={"error": {"code": code, "message": API_KEY}})
                self.assertIsNone(error.remote_code)
                self.assertIn("绘图接口", error.message)
        error, _ = self.http_failure(body={"error": {"code": "evil code"}, "code": "SafeFallback"})
        self.assertEqual(error.remote_code, "SafeFallback")

    def test_http_error_body_reads_no_more_than_64_kib(self):
        raw = b'{"error":{"message":"' + b"x" * (MAX_ERROR_BYTES * 2) + API_KEY.encode() + b'"}}'
        error, stream = self.http_failure(502, raw, headers={"Content-Length": str(len(raw))})
        self.assertEqual(stream.read_sizes, [MAX_ERROR_BYTES])
        self.assertEqual(stream.bytes_read, MAX_ERROR_BYTES)
        self.assertEqual(error.http_status, 502)
        self.assertIsNone(error.remote_code)
        self.assertTrue(error.retryable)

    def test_http_error_body_read_failure_preserves_safe_diagnostics(self):
        stream = BytesIO(b"unused")
        failure = HTTPError("https://provider.example.test/v1/images/generations", 503, API_KEY,
                            {"x-request-id": "req-readable", "Content-Type": "application/json"}, stream)
        with patch.object(failure, "read", side_effect=OSError(API_KEY)), \
                patch("cocktail_service.provider.urlopen", side_effect=failure) as mocked:
            with self.assertRaises(ProviderError) as caught:
                self.provider.generate("Recipe preview", [], 27)
        self.assert_failure(caught.exception, "provider_http_error")
        self.assertEqual(caught.exception.http_status, 503)
        self.assertEqual(caught.exception.request_id, "req-readable")
        self.assertIsNone(caught.exception.remote_code)
        self.assertEqual(mocked.call_count, 1)

    def test_request_id_header_cannot_expose_secret_or_unsafe_text(self):
        for value in (API_KEY, "prefix-" + API_KEY, "bad request id", "x" * 201):
            with self.subTest(value=value):
                error, _ = self.http_failure(body={"code": "ModelNotFound"}, headers={"x-request-id": value})
                self.assertIsNone(error.request_id)
                self.assertEqual(error.remote_code, "ModelNotFound")

    def test_timeout_and_network_error_are_classified_without_retry(self) -> None:
        for failure, code in (
            (socket.timeout("network timeout"), "provider_timeout"),
            (URLError("network failed " + API_KEY), "provider_network_error"),
        ):
            with self.subTest(code=code):
                with patch("cocktail_service.provider.urlopen", side_effect=failure) as mocked:
                    with self.assertRaises(ProviderError) as caught:
                        self.provider.generate("Recipe preview", [], 28)
                self.assert_failure(caught.exception, code)
                self.assertEqual(mocked.call_count, 1)

    def test_download_failure_is_classified_without_retry(self) -> None:
        with patch(
            "cocktail_service.provider.urlopen",
            side_effect=[provider_response(), URLError("download failed " + API_KEY)],
        ) as mocked:
            with self.assertRaises(ProviderError) as caught:
                self.provider.generate("Recipe preview", [], 29)
        self.assert_failure(caught.exception, "image_download_failed")
        self.assertEqual(mocked.call_count, 2)

    def test_invalid_provider_json_and_missing_url_do_not_download(self) -> None:
        responses = [
            FakeResponse(b"not JSON " + API_KEY.encode("ascii")),
            provider_response(data=[]),
            provider_response(data=[{}]),
        ]
        for response in responses:
            with self.subTest(response=response):
                with patch("cocktail_service.provider.urlopen", return_value=response) as mocked:
                    with self.assertRaises(ProviderError) as caught:
                        self.provider.generate("Recipe preview", [], 30)
                self.assert_failure(caught.exception, "invalid_provider_response")
                self.assertEqual(mocked.call_count, 1)

    def test_provider_json_read_is_bounded(self) -> None:
        response = FakeResponse(b" " * (MAX_JSON_BYTES + 2))
        with patch("cocktail_service.provider.urlopen", return_value=response) as mocked:
            with self.assertRaises(ProviderError) as caught:
                self.provider.generate("Recipe preview", [], 31)
        self.assert_failure(caught.exception, "invalid_provider_response")
        self.assertEqual(mocked.call_count, 1)
        self.assertTrue(response.read_sizes)
        self.assertTrue(all(0 <= size <= MAX_JSON_BYTES + 1 for size in response.read_sizes))
        self.assertLessEqual(response.body.tell(), MAX_JSON_BYTES + 1)

    def test_download_read_is_bounded(self) -> None:
        response = FakeResponse(b"x" * (MAX_IMAGE_BYTES + 2))
        with patch(
            "cocktail_service.provider.urlopen",
            side_effect=[provider_response(), response],
        ) as mocked:
            with self.assertRaises(ProviderError) as caught:
                self.provider.generate("Recipe preview", [], 32)
        self.assert_failure(caught.exception, "image_too_large")
        self.assertEqual(mocked.call_count, 2)
        self.assertTrue(response.read_sizes)
        self.assertTrue(all(0 <= size <= MAX_IMAGE_BYTES + 1 for size in response.read_sizes))
        self.assertLessEqual(response.body.tell(), MAX_IMAGE_BYTES + 1)

    def test_bad_png_is_rejected_after_download(self) -> None:
        invalid_images = [
            b"\x89PNG\r\n\x1a\n" + b"this is not a PNG image",
            png_fixture()[:32],
            image_bytes(Image.new("RGB", (20, 20), "red"), "JPEG"),
        ]
        for invalid_image in invalid_images:
            with self.subTest(image=invalid_image[:16]):
                with patch(
                    "cocktail_service.provider.urlopen",
                    side_effect=[provider_response(), FakeResponse(invalid_image)],
                ):
                    with self.assertRaises(ProviderError) as caught:
                        self.provider.generate("Recipe preview", [], 33)
                self.assert_failure(caught.exception, "invalid_image")

    def test_download_content_length_mismatch_is_rejected(self) -> None:
        png = png_fixture()
        downloaded = FakeResponse(png, headers={"Content-Length": str(len(png) + 10)})
        with patch("cocktail_service.provider.urlopen", side_effect=[provider_response(), downloaded]) as mocked:
            with self.assertRaises(ProviderError) as caught:
                self.provider.generate("Recipe preview", [], 34)
        self.assert_failure(caught.exception, "image_download_failed")
        self.assertEqual(mocked.call_count, 2)

    def test_download_rejects_oversized_declared_length_before_reading(self) -> None:
        downloaded = FakeResponse(png_fixture(), headers={"Content-Length": str(MAX_IMAGE_BYTES + 1)})
        with patch("cocktail_service.provider.urlopen", side_effect=[provider_response(), downloaded]):
            with self.assertRaises(ProviderError) as caught:
                self.provider.generate("Recipe preview", [], 35)
        self.assert_failure(caught.exception, "image_too_large")
        self.assertEqual(downloaded.read_sizes, [])

    def test_broken_http_transfer_is_redacted_and_not_retried(self) -> None:
        with patch("cocktail_service.provider.urlopen", side_effect=IncompleteRead(API_KEY.encode(), 100)) as mocked:
            with self.assertRaises(ProviderError) as caught:
                self.provider.generate("Recipe preview", [], 36)
        self.assert_failure(caught.exception, "provider_network_error")
        self.assertEqual(mocked.call_count, 1)

    def test_non_http_image_url_is_rejected_before_download(self) -> None:
        with patch("cocktail_service.provider.urlopen", return_value=provider_response(data=[{"url": "file:///private/image.png"}])) as mocked:
            with self.assertRaises(ProviderError) as caught:
                self.provider.generate("Recipe preview", [], 37)
        self.assert_failure(caught.exception, "invalid_provider_response")
        self.assertEqual(mocked.call_count, 1)


class ImagingTests(unittest.TestCase):
    def read_result(self, png: bytes) -> Image.Image:
        self.assertTrue(png.startswith(b"\x89PNG\r\n\x1a\n"))
        with Image.open(BytesIO(png)) as output:
            output.load()
            self.assertEqual(output.format, "PNG")
            self.assertEqual(output.mode, "RGBA")
            self.assertEqual(output.size, (1024, 1024))
            return output.copy()

    def assert_centered_with_margin(self, output: Image.Image) -> None:
        alpha = output.getchannel("A")
        box = alpha.getbbox()
        self.assertIsNotNone(box)
        left, top, right, bottom = box
        width, height = right - left, bottom - top
        self.assertLessEqual(max(width, height), 782)
        self.assertGreaterEqual(max(width, height), 773)
        self.assertAlmostEqual((left + right) / 2, 512, delta=2)
        self.assertAlmostEqual((top + bottom) / 2, 512, delta=2)
        for border in ((0, 0, 1024, 1), (0, 1023, 1024, 1024), (0, 0, 1, 1024), (1023, 0, 1024, 1024)):
            self.assertEqual(alpha.crop(border).getextrema(), (0, 0))

    def assert_metadata(self, metadata: dict, source_size: list[int], method: str) -> None:
        self.assertIs(metadata["alpha"], True)
        self.assertEqual(metadata["background_method"], method)
        self.assertIs(metadata["needs_review"], True)
        self.assertEqual(metadata["source_size"], source_size)
        self.assertEqual(metadata["output_size"], [1024, 1024])
        self.assertAlmostEqual(metadata["margin_ratio"], 0.12, places=2)

    def test_genuine_alpha_preserves_semitransparency_and_centers_content(self) -> None:
        source = Image.new("RGBA", (160, 240), (0, 0, 0, 0))
        draw = ImageDraw.Draw(source)
        draw.rectangle((48, 25, 111, 214), fill=(220, 120, 32, 128))
        draw.rectangle((72, 60, 80, 100), fill=(255, 255, 255, 255))
        png, metadata = normalize_image(image_bytes(source))
        output = self.read_result(png)
        self.assert_metadata(metadata, [160, 240], "preserved_alpha")
        self.assert_centered_with_margin(output)
        alphas = set(output.getchannel("A").tobytes())
        self.assertIn(128, alphas)
        self.assertIn(255, alphas)

    def test_white_background_removal_preserves_enclosed_white_highlights(self) -> None:
        source = Image.new("RGB", (100, 160), (255, 255, 255))
        draw = ImageDraw.Draw(source)
        draw.rectangle((30, 20, 70, 140), fill=(75, 40, 20))
        draw.rectangle((33, 23, 67, 137), fill=(225, 145, 55))
        draw.rectangle((42, 35, 46, 65), fill=(255, 255, 255))
        png, metadata = normalize_image(image_bytes(source))
        output = self.read_result(png)
        self.assert_metadata(metadata, [100, 160], "edge_connected_near_white")
        self.assert_centered_with_margin(output)
        pixels = output.tobytes()
        self.assertGreater(sum(pixels[offset:offset + 4] == b"\xff\xff\xff\xff"
                               for offset in range(0, len(pixels), 4)), 100)
        self.assertEqual(output.getpixel((0, 0))[3], 0)

    def test_opaque_rgba_uses_background_removal(self) -> None:
        source = Image.new("RGBA", (100, 160), (249, 247, 245, 255))
        ImageDraw.Draw(source).rectangle((30, 20, 70, 140), fill=(225, 145, 55, 255))
        png, metadata = normalize_image(image_bytes(source))
        output = self.read_result(png)
        self.assert_metadata(metadata, [100, 160], "edge_connected_near_white")
        self.assert_centered_with_margin(output)

    def test_unsafe_colored_background_is_rejected(self) -> None:
        source = Image.new("RGB", (100, 160), (30, 80, 140))
        ImageDraw.Draw(source).rectangle((30, 20, 70, 140), fill=(225, 145, 55))
        with self.assertRaises(ProcessingError) as caught:
            normalize_image(image_bytes(source))
        self.assertTrue(caught.exception.code)
        self.assertTrue(caught.exception.message)

    def test_empty_or_all_white_image_is_rejected(self) -> None:
        sources = [
            Image.new("RGBA", (100, 160), (0, 0, 0, 0)),
            Image.new("RGB", (100, 160), (255, 255, 255)),
        ]
        for source in sources:
            with self.subTest(mode=source.mode):
                with self.assertRaises(ProcessingError):
                    normalize_image(image_bytes(source))

    def test_invalid_image_is_rejected(self) -> None:
        with self.assertRaises(ProcessingError) as caught:
            normalize_image(b"not an image")
        self.assertEqual(caught.exception.code, "invalid_image")
        self.assertTrue(caught.exception.message)


if __name__ == "__main__":
    unittest.main()
