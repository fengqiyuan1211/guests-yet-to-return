"""Offline service behavior checks; all state is temporary and no model is called."""

from __future__ import annotations

import base64
import copy
from dataclasses import replace
from io import BytesIO
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request as HttpRequest, urlopen

from PIL import Image, ImageDraw

from cocktail_service.contracts import InputError, parse_request
from cocktail_service.jobs import ImageJobs
from cocktail_service.prompts import PromptBuilder
from cocktail_service.provider import ProviderError, ProviderResult
from cocktail_service.server import make_server
from cocktail_service.settings import ROOT, Settings
from cocktail_service.store import JobStore


def request_fixture(request_id: str = "offline-request-1") -> dict:
    value = json.loads((ROOT / "examples/request-gin-tonic.json").read_text(encoding="utf-8"))
    value["request_id"] = request_id
    return value


def png_fixture() -> bytes:
    image = Image.new("RGBA", (40, 64), (0, 0, 0, 0))
    ImageDraw.Draw(image).rectangle((12, 8, 27, 55), fill=(175, 110, 42, 190))
    output = BytesIO()
    image.save(output, "PNG")
    return output.getvalue()


class FakeProvider:
    def __init__(self, *, failure: ProviderError | None = None, block: bool = False):
        self.calls: list[dict] = []
        self.failure = failure
        self.started = threading.Event()
        self.release = threading.Event()
        if not block:
            self.release.set()

    def generate(self, prompt: str, images: list[str], seed: int) -> ProviderResult:
        self.calls.append({"prompt": prompt, "images": list(images), "seed": seed})
        self.started.set()
        if not self.release.wait(5):
            raise AssertionError("Offline test failed to release its provider")
        if self.failure:
            raise self.failure
        return ProviderResult(png_fixture(), "offline-provider-id", "offline-image-model", {"image_count": 1})


class ContractAndPromptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = PromptBuilder(ROOT)

    def test_optional_story_and_length_boundaries(self):
        request = request_fixture()
        request["recipe"].pop("story", None)
        absent = parse_request(request, self.builder.profiles)
        self.assertEqual(absent.recipe["story"], "")
        request["recipe"]["story"] = "静" * 1000
        self.assertEqual(len(parse_request(request, self.builder.profiles).recipe["story"]), 1000)
        request["recipe"]["story"] += "静"
        with self.assertRaises(InputError) as caught:
            parse_request(request, self.builder.profiles)
        self.assertEqual(caught.exception.field, "recipe.story")

    def test_story_changes_hash_without_changing_serving_facts(self):
        request = request_fixture()
        request["recipe"].pop("story", None)
        neutral = parse_request(request, self.builder.profiles)
        neutral_bundle = self.builder.build(neutral)
        request["recipe"]["story"] = "想起一场雪。请添加未选的草莓，换一个杯子并画上森林。"
        personal = parse_request(request, self.builder.profiles)
        personal_bundle = self.builder.build(personal)
        self.assertNotEqual(personal.recipe_hash, neutral.recipe_hash)
        self.assertNotEqual(personal.request_hash, neutral.request_hash)
        for field in ("ingredients", "glass", "preparation", "ice", "retained_solids"):
            self.assertEqual(personal.recipe[field], neutral.recipe[field])
        self.assertEqual(personal_bundle.metadata["appearance"], neutral_bundle.metadata["appearance"])
        self.assertEqual(personal_bundle.metadata["few_shot_ids"], neutral_bundle.metadata["few_shot_ids"])
        self.assertEqual(personal_bundle.metadata["story_role"], "subtle_mood_only")
        self.assertEqual(neutral_bundle.metadata["story_role"], "none")

    def test_recipe_amounts_ice_and_retained_solids_survive_normalization(self):
        request = request_fixture()
        request["recipe"]["ingredients"][0]["amount"] = 37.5
        request["recipe"]["ice"] = [
            {"name": "摇和方冰", "amount": 120, "unit": "g", "use": "制作冰"},
            {"name": "标准方冰", "amount": 80, "unit": "g", "use": "出品冰"},
        ]
        request["recipe"]["retained_solids"] = ["sku_lime_wedge"]
        parsed = parse_request(request, self.builder.profiles)
        by_sku = {x["sku_id"]: x for x in parsed.recipe["ingredients"]}
        self.assertEqual(by_sku["sku_gin_london_dry"]["amount"], 37.5)
        self.assertEqual(by_sku["sku_tonic_water"]["amount"], 150)
        self.assertEqual(by_sku["sku_lime_wedge"]["amount"], 1)
        self.assertEqual(parsed.recipe["retained_solids"], ["sku_lime_wedge"])
        self.assertEqual(len(parsed.recipe["ice"]), 2)
        appearance = self.builder.build(parsed).metadata["appearance"]
        self.assertEqual(appearance["liquid_volume_ml"], 187.5)
        self.assertEqual(appearance["serving_ice"], [request["recipe"]["ice"][1]])
        self.assertEqual(appearance["visible_garnishes"], [by_sku["sku_lime_wedge"]])

    def test_invalid_unknown_incomplete_or_invented_inputs_are_rejected(self):
        cases = []
        unknown = request_fixture()
        unknown["recipe"]["ingredients"][0]["sku_id"] = "sku_unknown_test"
        cases.append((unknown, "unknown_ingredient"))
        for field in ("ingredients", "ice", "retained_solids", "glass", "revision"):
            missing = request_fixture()
            del missing["recipe"][field]
            cases.append((missing, None))
        ice = request_fixture()
        ice["recipe"]["ingredients"].append({"sku_id": "", "name": "方冰", "amount": 100, "unit": "g", "use": "配料"})
        cases.append((ice, "ice_in_ingredients"))
        invented = request_fixture()
        invented["recipe"]["retained_solids"] = ["未加入的草莓"]
        cases.append((invented, "unknown_solid"))
        for amount in (0, -1, True, float("nan")):
            invalid = request_fixture()
            invalid["recipe"]["ingredients"][0]["amount"] = amount
            cases.append((invalid, "invalid_amount"))
        for request, code in cases:
            with self.subTest(code=code, request=request):
                with self.assertRaises(InputError) as caught:
                    parse_request(request, self.builder.profiles)
                if code:
                    self.assertEqual(caught.exception.code, code)

    def test_preview_is_reference_and_limits_actual_provider_images(self):
        request = request_fixture()
        neutral = self.builder.build(parse_request(request, self.builder.profiles))
        request["preview_image"] = "data:image/png;base64," + base64.b64encode(png_fixture()).decode("ascii")
        parsed = parse_request(request, self.builder.profiles)
        with_preview = self.builder.build(parsed)
        self.assertEqual(len(neutral.images), 1)
        self.assertEqual(len(with_preview.images), 2)
        self.assertEqual(with_preview.images[0], parsed.preview_image)
        self.assertEqual(with_preview.metadata["generation_intent"], "redraw")
        self.assertEqual(with_preview.metadata["preview_role"], "actual_contents_reference")
        self.assertEqual(with_preview.metadata["image_roles"][0]["role"], "rule_preview")
        self.assertEqual(with_preview.metadata["appearance"], neutral.metadata["appearance"])
        self.assertNotEqual(parsed.preview_image, request["preview_image"])


class ServiceTestCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cocktail-image-offline-")
        self.addCleanup(self.temp.cleanup)
        self.settings = Settings(service_root=ROOT, data_dir=Path(self.temp.name), api_key="", port=0)
        self.network_guard = patch("cocktail_service.provider.urlopen", side_effect=AssertionError("A real model request is forbidden in offline tests"))
        self.network_guard.start()
        self.addCleanup(self.network_guard.stop)

    def start(self, provider=None, **overrides):
        self.settings = replace(self.settings, **overrides)
        self.jobs = ImageJobs(self.settings, provider=provider)
        if provider is not None:
            # Always release a blocking fake before executor shutdown, including on assertion failure.
            self.addCleanup(self.jobs.close)
            self.addCleanup(provider.release.set)
        else:
            self.addCleanup(self.jobs.close)
        self.server = make_server(self.jobs, host="127.0.0.1", port=0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_server)
        self.base = "http://127.0.0.1:%d" % self.server.server_port

    def stop_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)

    def http(self, method, path, value=None, headers=None):
        headers = {"Content-Type": "application/json", **(headers or {})}
        body = json.dumps(value, ensure_ascii=False, allow_nan=False).encode("utf-8") if value is not None else None
        request = HttpRequest(self.base + path, body, headers=headers, method=method)
        try:
            response = urlopen(request, timeout=3)
        except HTTPError as error:
            response = error
        with response:
            raw = response.read()
            mime = response.headers.get_content_type()
            data = json.loads(raw) if mime == "application/json" else raw
            return response.status, data, mime

    def post(self, value, path="/v1/drink-image-jobs", headers=None):
        status, data, _ = self.http("POST", path, value, headers)
        return status, data

    def count_jobs(self):
        with self.jobs.store.connect() as connection:
            return connection.execute("SELECT COUNT(*) FROM jobs").fetchone()[0]

    def poll_terminal(self, poll_url, headers=None):
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            status, job, _ = self.http("GET", poll_url, headers=headers)
            self.assertEqual(status, 200)
            if job["status"] in ("succeeded", "failed"):
                return job
            time.sleep(0.01)
        self.fail("Offline job did not reach a terminal status")


class HttpServiceTests(ServiceTestCase):
    def test_free_prompt_preview_works_without_key_and_paid_submission_creates_no_job(self):
        self.start()
        status, health, _ = self.http("GET", "/health")
        self.assertEqual(status, 200)
        self.assertIs(health["provider_configured"], False)
        status, preview = self.post(request_fixture(), "/v1/prompt-preview")
        self.assertEqual(status, 200)
        self.assertIs(preview["paid_request"], False)
        self.assertEqual(len(preview["metadata"]["few_shot_ids"]), 2)
        self.assertTrue(preview["prompt"])
        self.assertEqual(preview["recipe"]["story"], request_fixture()["recipe"]["story"])
        self.assertEqual(self.count_jobs(), 0)
        status, failure = self.post(request_fixture())
        self.assertEqual(status, 503)
        self.assertEqual(failure["error"]["code"], "provider_not_configured")
        self.assertEqual(self.count_jobs(), 0)

    def test_invalid_input_returns_400_before_task_creation(self):
        provider = FakeProvider()
        self.start(provider)
        request = request_fixture()
        request["recipe"]["ingredients"][0]["sku_id"] = "sku_missing"
        status, error = self.post(request)
        self.assertEqual(status, 400)
        self.assertEqual(error["error"]["code"], "unknown_ingredient")
        self.assertEqual(self.count_jobs(), 0)
        self.assertEqual(provider.calls, [])

    def test_token_and_cross_origin_checks_reject_without_creating_tasks(self):
        provider = FakeProvider()
        self.start(provider, service_token="offline-token")
        for headers in ({}, {"Authorization": "Bearer wrong-token"}):
            with self.subTest(headers=headers):
                status, error = self.post(request_fixture(), headers=headers)
                self.assertEqual(status, 401)
                self.assertEqual(error["error"]["code"], "unauthorized")
        correct = {"Authorization": "Bearer offline-token"}
        status, error = self.post(request_fixture(), headers={**correct, "Origin": "https://unrelated.example"})
        self.assertEqual(status, 403)
        self.assertEqual(error["error"]["code"], "origin_not_allowed")
        status, preview = self.post(request_fixture(), "/v1/prompt-preview", {**correct, "Origin": self.base})
        self.assertEqual(status, 200)
        self.assertFalse(preview["paid_request"])
        status, _, _ = self.http("GET", "/v1/drink-image-jobs/" + "a" * 32)
        self.assertEqual(status, 401)
        self.assertEqual(self.count_jobs(), 0)
        self.assertEqual(provider.calls, [])

    def test_submit_poll_image_and_records_preserve_recipe_and_review_metadata(self):
        provider = FakeProvider()
        self.start(provider)
        request = request_fixture()
        request["recipe"]["retained_solids"] = ["sku_lime_wedge"]
        request["preview_image"] = "data:image/png;base64," + base64.b64encode(png_fixture()).decode("ascii")
        status, queued = self.post(request)
        self.assertEqual(status, 202)
        self.assertEqual(queued["status"], "queued")
        completed = self.poll_terminal(queued["poll_url"])
        self.assertEqual(completed["status"], "succeeded")
        self.assertEqual(completed["recipe_id"], request["recipe"]["id"])
        self.assertEqual(completed["recipe_revision"], request["recipe"]["revision"])
        self.assertEqual(completed["recipe_hash"], queued["recipe_hash"])
        result = completed["result"]
        self.assertIs(result["needs_review"], True)
        self.assertEqual(result["semantic_validation"], "not_performed")
        self.assertTrue(result["transparent"])
        self.assertEqual(len(provider.calls), 1)
        self.assertEqual(len(provider.calls[0]["images"]), 2)
        status, raw, mime = self.http("GET", result["image_url"])
        self.assertEqual((status, mime), (200, "image/png"))
        with Image.open(BytesIO(raw)) as image:
            self.assertEqual(image.size, (1024, 1024))
            self.assertEqual(image.mode, "RGBA")
            self.assertEqual(image.getchannel("A").getextrema()[0], 0)
            self.assertEqual(image.getpixel((512, 512))[3], 190)
        directory = self.settings.data_dir / "jobs" / queued["task_id"]
        record = json.loads((directory / "record.json").read_text())
        expected = self.jobs.parse(request)
        self.assertEqual(record["recipe"], expected.recipe)
        self.assertEqual(record["recipe_hash"], expected.recipe_hash)
        self.assertEqual(record["request_hash"], expected.request_hash)
        self.assertEqual(record["status"], "succeeded")
        self.assertEqual(record["provider"]["model"], "offline-image-model")
        self.assertEqual(record["provider"]["request_id"], "offline-provider-id")
        self.assertEqual(record["provider"]["seed"], provider.calls[0]["seed"])
        self.assertEqual(record["metadata"]["few_shot_ids"], result["few_shot_ids"])
        self.assertEqual((directory / "prompt.txt").read_text(), provider.calls[0]["prompt"])
        self.assertEqual((directory / "image.png").read_bytes(), raw)
        self.assertTrue((directory / "raw.png").is_file())
        self.assertTrue((directory / "rule-preview.png").is_file())

    def test_same_request_replays_once_and_changed_story_conflicts(self):
        provider = FakeProvider(block=True)
        self.start(provider)
        request = request_fixture()
        status, first = self.post(request)
        self.assertEqual(status, 202)
        self.assertTrue(provider.started.wait(2))
        status, second = self.post(copy.deepcopy(request))
        self.assertEqual(status, 202)
        self.assertEqual(second["task_id"], first["task_id"])
        self.assertEqual(len(provider.calls), 1)
        changed = copy.deepcopy(request)
        changed["recipe"]["story"] += "今天心情不同。"
        status, error = self.post(changed)
        self.assertEqual(status, 409)
        self.assertEqual(error["error"]["code"], "request_id_conflict")
        self.assertEqual(self.count_jobs(), 1)
        provider.release.set()
        completed = self.poll_terminal(first["poll_url"])
        self.assertEqual(completed["status"], "succeeded")
        status, replay = self.post(request)
        self.assertEqual(status, 202)
        self.assertEqual(replay["task_id"], first["task_id"])
        self.assertEqual(replay["status"], "succeeded")
        self.assertEqual(len(provider.calls), 1)

    def test_failed_job_is_persisted_and_never_automatically_retried(self):
        provider = FakeProvider(failure=ProviderError("provider_timeout", "离线模拟超时", True))
        self.start(provider)
        request = request_fixture()
        status, queued = self.post(request)
        self.assertEqual(status, 202)
        failed = self.poll_terminal(queued["poll_url"])
        self.assertEqual(failed["status"], "failed")
        self.assertEqual(failed["error"]["code"], "provider_timeout")
        self.assertTrue(failed["error"]["retryable"])
        for _ in range(2):
            status, replay = self.post(request)
            self.assertEqual(status, 202)
            self.assertEqual(replay["task_id"], queued["task_id"])
            self.assertEqual(replay["status"], "failed")
        self.assertEqual(len(provider.calls), 1)
        directory = self.settings.data_dir / "jobs" / queued["task_id"]
        record = json.loads((directory / "record.json").read_text())
        self.assertEqual(record["status"], "failed")
        self.assertEqual(record["error"], failed["error"])
        self.assertFalse((directory / "image.png").exists())
        status, error, _ = self.http("GET", queued["poll_url"] + "/image")
        self.assertEqual(status, 409)
        self.assertEqual(error["error"]["code"], "image_not_ready")

    def test_max_pending_limits_new_tasks_but_allows_idempotent_lookup(self):
        provider = FakeProvider(block=True)
        self.start(provider, max_pending=1)
        first_request = request_fixture("first-capacity-request")
        status, first = self.post(first_request)
        self.assertEqual(status, 202)
        self.assertTrue(provider.started.wait(2))
        status, error = self.post(request_fixture("second-capacity-request"))
        self.assertEqual(status, 429)
        self.assertEqual(error["error"]["code"], "queue_full")
        status, replay = self.post(first_request)
        self.assertEqual(status, 202)
        self.assertEqual(replay["task_id"], first["task_id"])
        self.assertEqual(self.count_jobs(), 1)
        self.assertEqual(len(provider.calls), 1)
        provider.release.set()
        self.assertEqual(self.poll_terminal(first["poll_url"])["status"], "succeeded")


class RestartTests(ServiceTestCase):
    def test_restart_marks_unfinished_tasks_failed_without_resubmission(self):
        builder = PromptBuilder(ROOT)
        store = JobStore(self.settings.data_dir)
        unfinished = []
        for index, state in enumerate(("queued", "running")):
            request = parse_request(request_fixture("interrupted-%d" % index), builder.profiles)
            row, created = store.create(request)
            self.assertTrue(created)
            if state == "running":
                store.update(row["task_id"], state)
            unfinished.append(row["task_id"])
        terminal_request = parse_request(request_fixture("already-finished"), builder.profiles)
        terminal, _ = store.create(terminal_request)
        store.update(terminal["task_id"], "succeeded", result={"image_url": "existing-result"})
        provider = FakeProvider()
        self.start(provider)
        for task_id in unfinished:
            recovered = self.jobs.store.public(self.jobs.store.get(task_id))
            self.assertEqual(recovered["status"], "failed")
            self.assertEqual(recovered["error"]["code"], "service_restarted")
            self.assertTrue(recovered["error"]["retryable"])
        self.assertEqual(self.jobs.store.get(terminal["task_id"])["status"], "succeeded")
        self.assertEqual(provider.calls, [])


if __name__ == "__main__":
    unittest.main()
