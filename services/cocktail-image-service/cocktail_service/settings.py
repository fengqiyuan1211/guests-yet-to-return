from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read_env(path: Path) -> dict[str, str]:
    """Read literal KEY=value pairs; never execute or expand shell expressions."""
    values = {}
    if path.is_file():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, separator, value = line.partition("=")
            if not separator or not key.strip().replace("_", "").isalnum():
                raise ValueError(".env 中存在无效配置行。")
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            values[key.strip()] = value
    return {**values, **os.environ}


@dataclass(frozen=True)
class Settings:
    service_root: Path = ROOT
    data_dir: Path = ROOT / "var"
    host: str = "127.0.0.1"
    port: int = 8787
    api_key: str = ""
    base_url: str = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    model: str = "qwen-image-3.0"
    timeout: float = 600.0
    output_size: int = 1024
    service_token: str = ""
    workers: int = 1
    max_pending: int = 16
    reference_images: bool = True
    use_system_proxy: bool = False

    @classmethod
    def from_env(cls, root: Path = ROOT) -> "Settings":
        env = read_env(root / ".env")
        value = cls(
            service_root=root,
            data_dir=Path(env.get("IMAGE_DATA_DIR", str(root / "var"))).expanduser().resolve(),
            host=env.get("IMAGE_SERVICE_HOST", "127.0.0.1"),
            port=int(env.get("IMAGE_SERVICE_PORT", "8787")),
            api_key=env.get("DASHSCOPE_API_KEY", "").strip(),
            base_url=env.get("QWEN_BASE_URL", cls.base_url).rstrip("/"),
            model=env.get("QWEN_IMAGE_MODEL", cls.model),
            timeout=float(env.get("QWEN_TIMEOUT_SECONDS", "600")),
            service_token=env.get("IMAGE_SERVICE_TOKEN", ""),
            workers=int(env.get("IMAGE_WORKERS", "1")),
            max_pending=int(env.get("IMAGE_MAX_PENDING", "16")),
            reference_images=env.get("IMAGE_REFERENCE_IMAGES", "true").lower() == "true",
            use_system_proxy=env.get("QWEN_USE_SYSTEM_PROXY", "false").lower() == "true",
        )
        if value.host not in ("127.0.0.1", "localhost", "::1") and not value.service_token:
            raise ValueError("开放给其他电脑前，请设置 IMAGE_SERVICE_TOKEN。")
        if not 1 <= value.workers <= 4 or not 1 <= value.max_pending <= 100:
            raise ValueError("工作线程或队列容量超出范围。")
        if not 1 <= value.port <= 65535 or not 30 <= value.timeout <= 1800:
            raise ValueError("端口或接口超时时间无效。")
        if not value.base_url.startswith("https://"):
            raise ValueError("QWEN_BASE_URL 必须是 HTTPS 接口。")
        return value
