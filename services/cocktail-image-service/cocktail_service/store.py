from __future__ import annotations

import json
import sqlite3
import time
import uuid
from contextlib import contextmanager
from pathlib import Path

from .contracts import Request, canonical


class StoreError(Exception):
    def __init__(self, code: str, message: str, http_status: int):
        super().__init__(message)
        self.code, self.message, self.http_status = code, message, http_status


class JobStore:
    def __init__(self, root: Path, max_pending: int = 16):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.database = root / "jobs.sqlite3"
        self.max_pending = max_pending
        with self.connect() as connection:
            connection.execute("PRAGMA journal_mode=WAL")
            connection.execute("""CREATE TABLE IF NOT EXISTS jobs (
              task_id TEXT PRIMARY KEY, request_id TEXT UNIQUE NOT NULL,
              request_hash TEXT NOT NULL, recipe_id TEXT NOT NULL, revision INTEGER NOT NULL,
              recipe_hash TEXT NOT NULL, recipe TEXT NOT NULL, status TEXT NOT NULL,
              created REAL NOT NULL, updated REAL NOT NULL, result TEXT, error TEXT)""")

    @contextmanager
    def connect(self):
        connection = sqlite3.connect(self.database, timeout=10)
        connection.row_factory = sqlite3.Row
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def recover_interrupted(self):
        error = canonical({"code": "service_restarted", "message": "服务重启时这个任务尚未完成；请用新的 request_id 手动再试。", "retryable": True})
        with self.connect() as connection:
            connection.execute("UPDATE jobs SET status='failed', updated=?, error=? WHERE status IN ('queued','running')", (time.time(), error))

    def create(self, request: Request):
        with self.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            previous = connection.execute("SELECT * FROM jobs WHERE request_id=?", (request.request_id,)).fetchone()
            if previous:
                if previous["request_hash"] != request.request_hash:
                    raise StoreError("request_id_conflict", "同一 request_id 已绑定另一份配方或预览图；修改后请使用新 ID。", 409)
                return dict(previous), False
            pending = connection.execute("SELECT COUNT(*) FROM jobs WHERE status IN ('queued','running')").fetchone()[0]
            if pending >= self.max_pending:
                raise StoreError("queue_full", "出图队列已满，请稍后提交。", 429)
            task_id, now = uuid.uuid4().hex, time.time()
            connection.execute("INSERT INTO jobs VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", (task_id, request.request_id, request.request_hash, request.recipe["id"], request.recipe["revision"], request.recipe_hash, canonical(request.recipe), "queued", now, now, None, None,))
            row = connection.execute("SELECT * FROM jobs WHERE task_id=?", (task_id,)).fetchone()
            return dict(row), True

    def get(self, task_id):
        with self.connect() as connection:
            row = connection.execute("SELECT * FROM jobs WHERE task_id=?", (task_id,)).fetchone()
        return dict(row) if row else None

    def update(self, task_id, status, result=None, error=None):
        with self.connect() as connection:
            connection.execute("UPDATE jobs SET status=?,updated=?,result=?,error=? WHERE task_id=?", (status, time.time(), canonical(result) if result is not None else None, canonical(error) if error is not None else None, task_id))

    def public(self, row):
        value = {"task_id": row["task_id"], "request_id": row["request_id"], "status": row["status"], "recipe_id": row["recipe_id"], "recipe_revision": row["revision"], "recipe_hash": row["recipe_hash"], "poll_url": f"/v1/drink-image-jobs/{row['task_id']}", "created_at": row["created"], "updated_at": row["updated"]}
        if row["result"]:
            value["result"] = json.loads(row["result"])
        if row["error"]:
            value["error"] = json.loads(row["error"])
        if row["status"] in ("succeeded", "failed") and (self.root / "jobs" / row["task_id"] / "raw.png").is_file():
            # This is a review preview, separate from a successfully processed
            # game asset. Never expose it as result.image_url after a failure.
            value["raw_image_url"] = f"/v1/drink-image-jobs/{row['task_id']}/raw-image"
        return value
