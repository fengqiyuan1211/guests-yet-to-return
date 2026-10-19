"""Offline checks for inaccessible storage; never invokes an image provider."""
import json
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, build_opener, ProxyHandler
from cocktail_service.store import JobStore
from cocktail_service.server import make_server

class StorageHealthTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.store = JobStore(self.root)
        self.settings = SimpleNamespace(service_token="", host="127.0.0.1", port=0,
                                        model="offline", data_dir=self.root, service_root=self.root)
        self.jobs = SimpleNamespace(settings=self.settings, store=self.store, configured=True,
                                    env_stamp=None, configuration_changed=lambda:False)
        self.server = make_server(self.jobs)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.close)

    def close(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join()

    def request(self, path, payload=None):
        req = Request("http://127.0.0.1:%d%s" % (self.server.server_port, path),
                      data=json.dumps(payload).encode() if payload is not None else None,
                      headers={"Content-Type":"application/json"})
        try:
            response = build_opener(ProxyHandler({})).open(req, timeout=3)
        except HTTPError as error:
            response = error
        with response:
            return response.status, json.loads(response.read())

    def test_real_health_checks_database_and_directory_without_jobs(self):
        code, value = self.request("/health")
        self.assertEqual(code, 200)
        self.assertTrue(value["storage_ready"])
        with self.store.connect() as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM jobs").fetchone()[0], 0)
        self.assertFalse(any(x.name.startswith("tmp") for x in self.root.iterdir()))

    def test_storage_failure_is_not_reported_ready(self):
        with patch.object(self.store, "check_storage", side_effect=sqlite3.OperationalError("private path")):
            code, value = self.request("/health")
        self.assertEqual(code, 503)
        self.assertEqual(value["status"], "unavailable")
        self.assertNotIn("private path", json.dumps(value))

    def test_config_access_failure_does_not_disconnect(self):
        self.jobs.configuration_changed=lambda: (_ for _ in ()).throw(PermissionError("secret"))
        code, value = self.request("/health")
        self.assertEqual(code, 503)
        self.assertNotIn("secret", json.dumps(value))

    def test_get_job_storage_error_returns_actionable_json(self):
        with patch.object(self.store, "get", side_effect=sqlite3.OperationalError("private path")):
            code, value = self.request("/v1/drink-image-jobs/" + "a" * 32)
        self.assertEqual(code, 503)
        self.assertEqual(value["error"]["code"], "storage_unavailable")

    def test_submit_storage_failure_is_not_retried(self):
        calls=[]
        def create(_):
            calls.append(1)
            raise sqlite3.OperationalError("private path")
        self.jobs.create=create
        code, value = self.request("/v1/drink-image-jobs", {})
        self.assertEqual(code, 503)
        self.assertEqual(calls, [1])
        self.assertEqual(value["error"]["code"], "storage_unavailable")

if __name__ == "__main__": unittest.main()
