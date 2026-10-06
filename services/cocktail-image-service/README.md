# DIY 鸡尾酒自动出图服务

将玩家实际保存的配方生成一张符合酒馆手绘风格的成品图。提供 Python 服务、本地测试页面、Godot 客户端，以及项目内的开发 skill。

2026-10-07：已接入游戏研发结果页。完成 DIY 后填写酒名、可选故事和复做笔记 → 生成手绘酒图 → 玩家确认 → 保存成品到研发配方库及图鉴 DIY 分类。传说配方完美研习后也可生成并保存封面。模型只生成图片，不修改配方、属性、库存或评分。

## 先试起来

需要 Python 3.10 或更新版本。在本目录打开终端：

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
cp .env.example .env
```

用文本编辑器打开 `.env`，填写自己的 `DASHSCOPE_API_KEY`。默认配置为北京地域的 `qwen-image-3.0`；密钥、模型和地址需要属于同一地域。若使用业务空间专属域名，改 `QWEN_BASE_URL` 为对应的完整地址，例如 `https://你的业务空间ID.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`。可将模型切换为 `qwen-image-3.0-pro`。

```bash
python run.py
```

在浏览器打开 [本地测试页面](http://127.0.0.1:8787)。页面有一份可以直接使用的配方：

1. 修改配方、可选故事、可选预览图。
2. 点“检查配方与提示词”：免费，不调用千问，可在未填写密钥时使用。
3. 点“生成酒图”：每次点击提交一个新生成任务，会使用千问额度。完成后检查酒图并下载透明 PNG。

Demo 默认预填 DIY 测试酒「荒原绿灯」：绿查特酒 80 ml、伏特加 10 ml、青柠汁 10 ml、鸡尾酒樱桃 2 颗，古典杯内放 1 块大方冰。预期为偏浓黄绿色酒液、矮宽厚底杯、无气泡；没有薄荷或柑橘片。它与现有经典酒的杯型和出品组合有明显差别，适合检查模型是否只遵循本次配方。完整请求见 `examples/request-green-lantern.json`，原金汤力示例仍可单独使用。

密钥只填写在服务端 `.env`，不用提供给聊天工具，也不要放在 Godot 工程脚本中。`.env`、运行数据和虚拟环境已被本目录 `.gitignore` 排除。**修改配置后需要停止并重新启动服务**，刷新网页不会重新加载密钥。服务检测到 `.env` 变化时会提示重启，并阻止用过时配置提交新的出图任务；已有任务仍可查询。Windows 可用 `py -m venv .venv`，再执行 `.venv\Scripts\Activate.ps1`，其余流程相同。

按 Ctrl+C 退出时，会等已开始的任务完成保存；强制退出后重启，会把中断任务标记为失败，不自动重新消费额度。一个存储目录只启动一个服务实例。

## 输入约定

完整范例：[examples/request-gin-tonic.json](examples/request-gin-tonic.json)。Godot 调用及完整字段说明：[游戏接入说明](../../docs/DIY酒图自动生成服务.md)。

主要字段是 `recipe.id/revision/name/ingredients/glass/preparation/ice/retained_solids`，可选 `recipe.story` 和 `preview_image`。实际用量必须是有限正数；冰不算原料，独立记录制作冰与出品冰；无冰、无留杯固体时对应数组传 `[]`。不要把没有在成品里留下的冰或果肉画出来。

已知原料用现有 `sku_id`，名字由冻结的原料资料规范化。自定义原料可省略 SKU，提供 `name`；尚无视觉资料时使用近似规则并提示人工确认。增加正式 SKU 时要同步更新 `config/visual_profiles.json`。它包含现有全部 22 个消耗品，颜色是美术近似，没有模拟混合化学或推算酒精度。

`preview_image` 接受可选的 PNG/JPEG Base64 data URL，原图不超过 5 MB、800 万像素。不接收本机路径或用户提供的远程 URL。它仅参考颜色、液面；有图无图都重新绘制，美化杯身、酒液和真实装饰。界面上的粗糙杯子不会成为必须保留的轮廓。

`recipe.story` 是可选的故事或心情，最多 1000 个字符。它只影响细微的光感、笔触氛围，不改变用量、色调、杯型、冰或装饰，不生成故事中的场景、人物或文字。名称、故事和原料名都是数据，不作为执行指令。

修改配方、杯型、制作方法或故事后，增加 `revision` 并生成新的 `request_id`。同一请求重发时复用原 `request_id`，避免重复提交；同 ID 更换内容会返回 `409`。不要为了重试不断更换编号。

## 固定画风与 few-shot

- 固定风格：`saloon-cocktail-cutout-v1`，与现有五杯经典酒一致。
- 固定五组“实际配方 → 外观说明 → 成品参考图”，存于 [config/few_shots.json](config/few_shots.json)。参考图直接冻结已有图片并登记 SHA-256，来源见 `config/provenance.json`。
- 每次按杯型和近似颜色稳定选择两组。可选预览图排第一，再加两张风格图，总数最多三张；不提供预览也保留两张风格参考。
- 参考酒图只指导笔触、玻璃表现和构图，不允许复制它们的原料或装饰。例子的故事也不能改变目标配方。
- 固定 `prompt_version`、种子、尺寸、`prompt_extend=false` 和 `watermark=false`。每个任务保存实际提示词、参考角色及图片哈希、配方/请求哈希、种子、模型与服务返回编号。

固定参数有助于稳定产出，但模型更新或重新请求仍可能得到不同图片。首次使用时请用几种实际配方检查颜色、杯型、出品冰、装饰和整体画风，再决定是否调整提示词版本。更新样例图片时需同步哈希，避免无记录的风格变化。

### 配方可见内容约束

当前版本为 `diy-cocktail-handdrawn-v4`。每次从实际配方生成可见食材清单、未选择装饰的否定示例、杯型轮廓和出品冰规则，并保存到 `metadata.serving_constraints`。原料香气、故事、预览图和参考图不能授权增加实体食材。确实选用了薄荷或明确保留薄荷叶时允许出现，没有选择时明确禁止。

古典杯强调矮宽、厚底及无杯脚，其他杯型各有轮廓提示；杯身比例只是游戏美术参考，不是器具尺寸标准。按 `piece` 记录的冰遵循数量，1 块大方冰不能拆成多块或碎冰；按 `g` 记录的冰不擅自换算固定块数。装饰数量按原单位保留。无装饰时仍允许配方明确指定的留杯固体。

这些是生成提示约束，尚不是图片语义自动校验。结果仍保留 `needs_review=true`，实际生成效果需要查看成图确认；不能把新增约束当成模型已经正确执行的证据。

如仅想验证无图路径，可将 `IMAGE_REFERENCE_IMAGES=false`，且不上传预览图；仍提供文字 few-shot。正常使用建议保留图片参考。

## 接口与存储

| 请求 | 返回 |
| --- | --- |
| `GET /health` | 服务状态及 `provider_configured`，不暴露密钥。 |
| `POST /v1/prompt-preview` | 规范化配方、免费提示词和参考记录。 |
| `POST /v1/drink-image-jobs` | `202`，包含任务 ID 和相对轮询地址。 |
| `GET /v1/drink-image-jobs/<task_id>` | 排队、生成中、成功或失败状态。 |
| `GET /v1/drink-image-jobs/<task_id>/image` | 成功结果 PNG。 |
| `GET /v1/drink-image-jobs/<task_id>/raw-image` | 已下载的原始生成图，供检查，不代表透明素材处理成功。 |

任务状态：`queued → running → succeeded / failed`。失败有 `error.code/message/retryable`，但服务不会自动重试付费生成。网络超时可能已消耗上游额度，应先查看原任务。`needs_review=true` 表示图片仍需检查；JSON/PNG 校验不等于配方视觉正确。

成功结果为 1024 × 1024 RGBA PNG，中心放置、约 12% 空白边距。模型先画纯白背景，再在必要时保守移除与边缘相连的近白背景；已有透明图保留其透明度。非安全背景会报错，不假称透明。半透明玻璃与白色装饰可能需要进一步人工检查；保留 `raw.png` 便于后续改进抠图。

若图片已下载但背景处理失败，任务仍为 `failed`，额外提供 `raw_image_url`。测试页面会展示原图及失败原因，原图不能作为成功的游戏素材。成功任务也可切换查看原图。刷新页面恢复当前会话中最近的任务；也可用 `/?task=<任务 ID>` 查看已保存任务。这些查看操作不会重新调用模型。

服务保存到本目录 `var/`（可配置 `IMAGE_DATA_DIR`）：

```text
var/
  jobs.sqlite3
  jobs/<task_id>/
    record.json       配方、故事、模型及处理记录
    prompt.txt        本次最终提示词
    rule-preview.png  有预览图时保存
    raw.png           模型原图，下载成功后保存
    image.png         处理后的透明成品图
```

SQLite 只保存任务，不承担现有游戏成品/库存数据库。临时模型图片 URL 被立即下载，不能作为长期酒谱图片地址。Godot 下载到 `user://diy_cocktails/images/` 并通过 `image_ready` 返回纹理和路径，游戏已通过 research_image_dialog.gd 和 research_image_request.gd 接入，具体传输见 [diy_image_client.gd](../../scripts/diy_image_client.gd)。当前经典数据库只加载 `res://` 图片，DIY 图片应通过独立的运行时数据桥接层保存，不能直接塞进静态目录冒充经典酒。

默认每次一个工作线程、最多 16 个未完成任务。可用 `IMAGE_WORKERS` 和 `IMAGE_MAX_PENDING` 调整。任务与图片不会自动清理；实验数据多了之后需按游戏产品需求添加保留策略。

## 千问协议

当前适配使用千问 OpenAI 兼容的 `POST /images/generations`，带顶层 `image` 扩展字段传参考图，尺寸写作 `1024x1024`。不使用 `/images/edits`、multipart 或 mask。千问同步生成由本服务后台执行，游戏只轮询本服务；无参考时省略 `image` 字段。协议依据：[阿里云官方 API 文档](https://help.aliyun.com/zh/model-studio/qwen-image-generation-and-editing-api-reference)。

修改服务地址时保持对应地域；旧北京域名当前仍可用。未来若更换提供商，修改 `cocktail_service/provider.py`，保留输入契约、图像处理和任务接口。

本机测试默认绑定 `127.0.0.1`。手机或朋友电脑接入时需要设置可达地址，并配置独立的 `IMAGE_SERVICE_TOKEN`；Godot 只保存这个服务口令。正式开放给玩家前，需要再做登录授权、HTTPS、用户额度和服务部署；当前没有面向公网的多用户身份体系。

## 离线验证与后续开发

```bash
python -m unittest discover -s tests -v
```

测试使用假模型和临时目录，不调用付费接口。服务与 Godot 客户端的模拟验收只证明流程可运行；真实千问的画面质量必须填好密钥后用实际配方验收。

项目 skill：[cocktail-image-service/SKILL.md](../../.agents/skills/cocktail-image-service/SKILL.md)。后续可让开发助手“按 cocktail-image-service skill 接入研发页面”。skill 是开发指南，游戏调用的是服务 API。

下一步接入顺序：保存玩家配方及版本 → 调用 `DiyImageClient` → 显示进度与生成预览 → 玩家确认 → 保存该版本的 `user://` 图片引用 → 放入 DIY 图鉴与酒单。不要让旧版本的出图回调覆盖新配方。
