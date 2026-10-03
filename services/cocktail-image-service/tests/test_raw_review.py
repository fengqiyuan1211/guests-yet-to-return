"""Review downloaded output without retrying generation or accepting a bad asset."""

from io import BytesIO
from unittest.mock import patch

from PIL import Image, ImageDraw

from cocktail_service.provider import ProviderError
from tests.test_service import FakeProvider, ServiceTestCase, request_fixture


def unsafe_png():
    image = Image.new("RGB", (80, 80), (215, 213, 211))
    ImageDraw.Draw(image).rectangle((20, 12, 60, 68), fill=(110, 75, 42))
    out = BytesIO()
    image.save(out, "PNG")
    return out.getvalue()


class RawReviewTests(ServiceTestCase):
    def test_failed_processing_exposes_original_with_auth_but_never_a_game_asset(self):
        provider = FakeProvider()
        self.start(provider, service_token="offline-token")
        headers = {"Authorization": "Bearer offline-token"}
        original = unsafe_png()
        with patch("tests.test_service.png_fixture", return_value=original):
            status, queued = self.post(request_fixture(), headers=headers)
            self.assertEqual(status, 202)
            failed = self.poll_terminal(queued["poll_url"], headers)
        self.assertEqual(failed["status"], "failed")
        self.assertEqual(failed["error"]["code"], "unsafe_background")
        self.assertIn("图片已生成", failed["error"]["message"])
        self.assertNotIn("result", failed)
        raw_url = failed["raw_image_url"]
        self.assertEqual(raw_url, queued["poll_url"] + "/raw-image")
        status, _, _ = self.http("GET", raw_url)
        self.assertEqual(status, 401)
        status, downloaded, mime = self.http("GET", raw_url, headers=headers)
        self.assertEqual((status, mime, downloaded), (200, "image/png", original))
        status, data, _ = self.http("GET", queued["poll_url"] + "/image", headers=headers)
        self.assertEqual(status, 409)
        self.assertEqual(data["error"]["code"], "image_not_ready")
        # Reviewing/restoring the same task never submits another paid request.
        self.http("GET", raw_url, headers=headers)
        self.poll_terminal(queued["poll_url"], headers)
        self.assertEqual(len(provider.calls), 1)

    def test_success_has_separate_processed_and_original_resources(self):
        provider = FakeProvider()
        self.start(provider)
        _, queued = self.post(request_fixture())
        completed = self.poll_terminal(queued["poll_url"])
        self.assertEqual(completed["status"], "succeeded")
        status, original, mime = self.http("GET", completed["raw_image_url"])
        self.assertEqual((status, mime), (200, "image/png"))
        status, processed, _ = self.http("GET", completed["result"]["image_url"])
        self.assertEqual(status, 200)
        self.assertNotEqual(original, processed)
        self.assertEqual(len(provider.calls), 1)

    def test_provider_failure_and_noncanonical_paths_do_not_expose_a_raw_image(self):
        provider = FakeProvider(failure=ProviderError("provider_http_error", "绘图接口暂不可用。"))
        self.start(provider)
        _, queued = self.post(request_fixture())
        failed = self.poll_terminal(queued["poll_url"])
        self.assertNotIn("raw_image_url", failed)
        status, data, _ = self.http("GET", queued["poll_url"] + "/raw-image")
        self.assertEqual(status, 409)
        self.assertEqual(data["error"]["code"], "raw_image_not_ready")
        for path in (queued["poll_url"] + "/raw.png", queued["poll_url"] + "/raw-image/extra"):
            status, _, _ = self.http("GET", path)
            self.assertEqual(status, 404)
        self.assertEqual(len(provider.calls), 1)
