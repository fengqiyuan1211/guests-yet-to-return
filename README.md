# 致未归的客人

**Guests Yet to Return**

一款以调酒、酒馆经营与人物故事为核心的 2D 游戏，使用 Godot 开发。

在海边的酒馆里，你将为来访的客人调制饮品，听他们讲述各自的经历。从一杯酒开始，慢慢认识坐在吧台另一侧的人，也为那些尚未归来的客人留一个位置。

![海边的酒馆](assets/pixel_b/harbor.png)

## 游戏内容

- **亲手调酒**：量取原料、加冰、摇和或搅拌，再选用合适的杯具与装饰。材料比例和制作方式共同决定成品表现。
- **经营酒馆**：采购原料、管理库存、编排营业酒单，根据客人的口味制作饮品。
- **认识客人**：在多次来访和对话中了解人物故事，参与与他们有关的小游戏，收集纪念物与专属配方。
- **研发配方**：自由搭配材料，为自己的酒命名、记录制作方法，并收藏到配方库。
- **收集图鉴**：查看酒品的原料、风味、制作步骤与故事，逐步丰富自己的酒谱。

## 开始游戏

### 运行环境

- **Godot 4.7.2**，使用 **Compatibility** 渲染器。
- 键盘与鼠标。
- 可选 AI 功能需要 **Python 3.10 或更新版本**，以及对应服务商的 API 配置。

### 从源码运行

1. 克隆本仓库，或下载并解压源码。
2. 在 Godot 项目管理器中导入根目录的 `project.godot`。
3. 等待首次资源导入完成，按 **F5** 启动游戏。

macOS 用户也可以在安装 Godot 后双击 `启动游戏.command`。若 Godot 位于自定义位置，可通过 `GODOT_BIN` 指定程序路径。

主场景为 `scenes/title_screen.tscn`。首次游玩可跟随序章和调酒教学熟悉操作，各小游戏的操作方式会在进入时说明。

## 可选 AI 功能

游戏提供客人饮后对话和 DIY 酒图生成两项可选功能。未配置服务时，饮后对话使用本地文本，DIY 配方仍可正常制作和保存。

| 功能 | 服务目录 | 默认端口 |
| --- | --- | --- |
| 根据配方生成 DIY 酒图 | `services/cocktail-image-service/` | `8787` |
| 根据饮品与客人经历生成饮后对话 | `services/customer-feedback-service/` | `8788` |

在对应服务目录中，将 `.env.example` 复制为 `.env`，填写自己的 API 密钥、模型和接口地址。酒图服务还需安装 `requirements.txt` 中的依赖；饮后对话服务仅使用 Python 标准库。

配置完成后，桌面端游戏会尝试自动启动本地服务，也可以在各服务目录中运行 `python run.py`。修改配置后需要重启对应服务。模型调用会使用所配置服务商的额度；`.env` 不应提交到仓库。

详细说明：

- [DIY 酒图服务配置](services/cocktail-image-service/README.md)
- [本地服务启动与排查](docs/本地服务自动启动.md)

## 项目结构

| 目录 | 内容 |
| --- | --- |
| `scenes/` | 游戏场景 |
| `scripts/` | 游戏逻辑与界面 |
| `shaders/` | 着色器与视觉效果 |
| `assets/` | 图片、字体、音频等素材 |
| `data/` | 配方、原料、剧情和小游戏配置 |
| `services/` | 可选 AI 服务 |
| `tests/` | 自动化测试与独立存档运行器 |
| `tools/` | 启动及开发工具 |
| `docs/` | 系统设计与接口文档 |

## 开发与测试

可通过 `启动工作台.command` 直接进入调酒工作台。在仓库根目录运行以下命令，可检查剧情、调酒、经营和配方保存等流程：

```sh
python3 tests/run_unified_story_flow.py --godot /path/to/Godot
```

将 `/path/to/Godot` 替换为本机 Godot 可执行文件路径。该运行器使用独立测试存档，不影响玩家进度。

酒图服务的离线测试可在 `services/cocktail-image-service/` 目录中运行：

```sh
python -m unittest discover -s tests
```

玩家进度保存在 Godot 的 `user://` 目录中，与项目源码分开存储。

## 问题反馈

欢迎通过 [Issues](https://github.com/fengqiyuan1211/guests-yet-to-return/issues) 提交问题或建议。报告问题时，请附上操作系统、Godot 版本、复现步骤，以及相关截图或报错信息。

## 素材与致谢

感谢 Godot 社区及项目所使用素材的创作者。音乐和音效的来源与署名见：

- [背景音乐](assets/audio/music/README.md)
- [序章音频](assets/audio/opening/README.md)
- [界面音效](assets/audio/interface/README.md)
- [调酒音效](assets/audio/workbench/CREDITS.md)

第三方素材的使用范围以各自的授权说明为准。
