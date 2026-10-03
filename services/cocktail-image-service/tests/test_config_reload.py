"""A changed .env must not silently submit a paid job with stale credentials."""
import json
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

from cocktail_service.jobs import ImageJobs, ServiceError
from cocktail_service.prompts import PromptBuilder
from cocktail_service.settings import Settings, ROOT


class NoCallsProvider:
    def generate(self, *_args):
        raise AssertionError("Stale settings must never call a provider")


class ConfigReloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.builder = PromptBuilder(ROOT)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="cocktail-env-change-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.settings = Settings(service_root=self.root, data_dir=self.root / "var")
        self.payload = json.loads((ROOT / "examples/request-gin-tonic.json").read_text())
        self.patch_builder = patch("cocktail_service.jobs.PromptBuilder", return_value=self.builder)
        self.patch_builder.start()
        self.addCleanup(self.patch_builder.stop)

    def start(self):
        self.jobs = ImageJobs(self.settings, provider=NoCallsProvider())
        self.addCleanup(self.jobs.close)

    def test_modified_env_blocks_new_job_before_it_is_queued(self):
        (self.root / ".env").write_text("DASHSCOPE_API_KEY=offline-old")
        self.start()
        self.assertFalse(self.jobs.configuration_changed())
        (self.root / ".env").write_text("DASHSCOPE_API_KEY=offline-new-longer")
        self.assertTrue(self.jobs.configuration_changed())
        with self.assertRaises(ServiceError) as caught:
            self.jobs.create(self.payload)
        self.assertEqual(caught.exception.code, "configuration_changed")
        with self.jobs.store.connect() as connection:
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM jobs").fetchone()[0], 0)

    def test_added_env_after_startup_also_requires_restart(self):
        self.start()
        (self.root / ".env").write_text("DASHSCOPE_API_KEY=offline-added")
        with self.assertRaises(ServiceError) as caught:
            self.jobs.create(self.payload)
        self.assertEqual(caught.exception.code, "configuration_changed")

    def test_existing_request_can_be_replayed_after_configuration_changes(self):
        self.start()
        request = self.jobs.parse(self.payload)
        original, _created = self.jobs.store.create(request)
        (self.root / ".env").write_text("DASHSCOPE_API_KEY=offline-added")
        replay = self.jobs.create(self.payload)
        self.assertEqual(replay["task_id"], original["task_id"])


if __name__ == "__main__":
    unittest.main()
