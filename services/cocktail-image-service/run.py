#!/usr/bin/env python3
"""Run the local recipe-to-art backend; provider secrets remain on this host."""
from cocktail_service.settings import Settings
from cocktail_service.jobs import ImageJobs
from cocktail_service.server import make_server


def main():
    jobs = server = None
    try:
        settings = Settings.from_env()
        jobs = ImageJobs(settings)
        server = make_server(jobs)
    except Exception:
        if jobs:
            jobs.close()
        print("启动失败：请检查 .env、端口、参考图完整性和 Pillow 是否已安装。")
        return 1
    address = "[" + settings.host + "]" if ":" in settings.host else settings.host
    print(f"酒图测试页面：http://{address}:{settings.port}")
    print("千问已配置。生成按钮会调用付费接口。" if jobs.configured else "尚未填写千问密钥。配方与提示词检查可以免费使用。")
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        print("正在关闭；已开始的出图任务会完成保存。")
    finally:
        server.server_close()
        jobs.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

