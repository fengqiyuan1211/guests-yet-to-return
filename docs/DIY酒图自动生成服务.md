# DIY 酒图自动生成服务

## 本轮范围

这套服务根据玩家实际保存的配方，生成一张符合酒馆现有手绘画风的透明成品酒图。它提供独立 HTTP 服务和 Godot 客户端。本轮尚未接入主页按钮、研发页面，也没有自动把结果写入图鉴或真实成品数据库。

服务启动、环境配置、模型费用和测试方法见 [服务 README](../services/cocktail-image-service/README.md)。默认地址为 `http://127.0.0.1:8787`。模型密钥只配置在服务端；Godot 不保存 DashScope 密钥。`service_token` 是可选的服务访问凭据，与模型密钥不同。

## 酒图如何保持风格

服务使用现有五杯酒的配方、外观描述和实际成品图作为 few-shot 参考，优先选择杯型相同、颜色接近的两张。提供玩家预览图时，参考图总数最多三张。

`preview_image` 只辅助说明颜色、液面和视觉意图。最终酒图会重新绘制杯身、酒液、冰和实际装饰，不会把粗略预览直接保存为成品，也不会固定沿用预览的粗糙轮廓。

配方是内容依据：图片只应展示实际加入且留在成品中的东西。过滤掉的薄荷、摇和时使用的制作冰、未添加的水果，不应凭空出现在图上。模型图像仍需要人工确认；`needs_review=true` 和 `semantic_validation="not_performed"` 表示尚未验证图中的配方语义。

玩家可以提供 `recipe.story`，写这杯酒的故事或当时的心情，最多 1000 个字符。故事只作为有限的视觉氛围参考，不能改变实际用料、酒液颜色、杯型、冰和装饰，也不能让图片增加文字或场景背景。客户端原样透传该字段；服务会把它保存到请求记录，并纳入配方哈希。

## 提交的数据

完整可运行示例见 [request-gin-tonic.json](../services/cocktail-image-service/examples/request-gin-tonic.json)。它对应现有金汤力的 50 ml 金酒、150 ml 汤力水、一块青柠角和 150 g 出品冰，使用独立 DIY 编号。

| 字段 | 约定 |
| --- | --- |
| `schema_version` | 固定为 `1`。 |
| `request_id` | 客户端幂等编号。Godot 未传时会生成 UUID；重试同一请求可复用该 UUID，修改配方后使用新编号。 |
| `recipe.id` | 稳定的配方编号，1–80 个英文字母、数字、下划线或短横线。 |
| `recipe.revision` | 从 `1` 开始的整数；原料、用量、杯型或制作方式变化时增加版本。 |
| `recipe.name` | 可选名称。不能单凭酒名让模型补出经典配方。 |
| `recipe.story` | 可选故事或心情，最多 1000 个字符；改变故事也应增加配方版本。 |
| `recipe.ingredients` | 实际使用的原料和装饰，包含 `sku_id`、`amount`、`unit`、`use`；已知 SKU 可省略 `name`。 |
| `recipe.glass` | 球形杯、高球杯、碟形杯、鸡尾酒杯或古典杯。 |
| `recipe.preparation` | 简短的实际制作流程，说明摇和、搅拌、过滤等。 |
| `recipe.ice` | 独立数组，记录名称、用量、单位和用途。无冰时传 `[]`，冰不写进原料数组。 |
| `recipe.retained_solids` | 留在成品里的固体名称或 SKU；必须来自实际配方，无留杯固体时传 `[]`。 |
| `preview_image` | 可选 PNG/JPEG 的 Base64 data URL，不接受本机路径或远程 URL。 |
| `style_id` | 固定为 `saloon-cocktail-cutout-v1`。 |

原料单位为 `ml`、`g`、`piece`、`sprig` 或 `dash`；用途为 `基酒`、`配料`、`制作香草` 或 `装饰`。不要把 dash 擅自换算成 ml。同一原料、同一用途和单位的重复行应先合并。

冰用途为 `制作冰` 或 `出品冰`，单位为 `g` 或 `piece`。例如摇壶内用冰属于制作冰，过滤到无冰杯中后不应绘出冰块；最终杯中另加的冰属于出品冰。

## HTTP 接口

| 请求 | 作用 |
| --- | --- |
| `GET /health` | 查看服务和 `provider_configured`；未配置模型时仍可查看提示词。 |
| `POST /v1/prompt-preview` | 免费构建提示词和参考信息，不提交付费生成任务。 |
| `POST /v1/drink-image-jobs` | 提交生成请求，返回 `202` 和任务信息。 |
| `GET /v1/drink-image-jobs/<task_id>` | 轮询 `queued`、`running`、`succeeded` 或 `failed`。 |
| `GET /v1/drink-image-jobs/<task_id>/image` | 下载成功任务的 PNG。 |
| `GET /v1/drink-image-jobs/<task_id>/raw-image` | 查看原始生成图，供审核，不代表已得到合格素材。 |

任务信息包含 `task_id`、`recipe_id`、`recipe_revision`、`recipe_hash`。提交结果还包含相对 `poll_url`。成功结果的 `result` 包含相对 `image_url`、尺寸、`mime_type="image/png"`、`transparent=true`、`style_id`、`recipe_hash` 和审核标记。失败结果提供 `error.code`、`error.message`、`error.retryable`。

图片已下载的终态任务还提供 `raw_image_url`。背景处理失败时可用它查看原图，但 `status` 仍为 `failed`，没有成功成品 `result`，不能把原图自动写入游戏素材。Demo 会展示失败原图，并可通过 `/?task=<task_id>` 恢复查看；这些操作不会再次提交付费生成。

客户端将每个任务绑定到提交时的配方编号、版本和服务返回的内容哈希，拒绝后续身份不一致的结果。`recipe_hash` 由服务规范化配方后计算，不要求游戏自行复制服务端的规范化算法。

## Godot 客户端

文件为 `scripts/diy_image_client.gd`，类名为 `DiyImageClient`。它是普通 `Node`，无需注册为全局单例。加入场景后调用 `generate_drink(request)`；该方法返回提交阶段的 `Error`，最终结果通过信号通知。

```gdscript
const ImageClientScript := preload("res://scripts/diy_image_client.gd")
var image_client: Node
var current_recipe_id := "diy_gin_tonic_example"
var current_recipe_revision := 1

func _ready() -> void:
    image_client = ImageClientScript.new()
    image_client.service_url = "http://127.0.0.1:8787"
    add_child(image_client)
    image_client.job_changed.connect(_on_image_job_changed)
    image_client.image_ready.connect(_on_image_ready)
    image_client.generation_failed.connect(_on_image_failed)

func request_saved_recipe_image(request: Dictionary) -> void:
    # 请求应来自已经保存的实际配方，而非展示用的酒名或模板。
    current_recipe_id = request.recipe.id
    current_recipe_revision = int(request.recipe.revision)
    var error: Error = image_client.generate_drink(request)
    if error != OK:
        print("本次酒图请求未提交：", error)

func _on_image_job_changed(info: Dictionary) -> void:
    # 客户端还会通知 submitting、downloading 和本地 cancelled 状态。
    print("酒图状态：", info.get("status", ""))

func _on_image_ready(recipe_id: String, revision: int, path: String,
        texture: Texture2D, info: Dictionary) -> void:
    if recipe_id != current_recipe_id or revision != current_recipe_revision:
        return
    # 在后续研发 UI 中预览 texture，并经确认后保存该版本的图片引用。
    # 此处还没有写入正式酒谱或替换旧图片。
    print("待确认酒图：", path, "，需要审核：", info.result.needs_review)

func _on_image_failed(code: String, message: String) -> void:
    print(message, " (", code, ")")
```

| 方法或信号 | 用法 |
| --- | --- |
| `generate_drink(request) -> Error` | 提交新任务，同时取消并忽略客户端原有生成。 |
| `poll() -> Error` | 手动查询当前任务；正在请求时返回 `ERR_BUSY`，默认已有定时轮询。 |
| `cancel()` | 停止本地 HTTP 和轮询，屏蔽旧结果；已提交服务端的任务可能继续执行，不保证取消费用。 |
| `is_generating()` | 查看本地是否仍在提交、等待或下载。 |
| `get_job_info()` | 获取独立副本，可显示进度及失败的 `retryable`。 |
| `job_changed(info)` | 提交、服务任务、下载、完成、取消和失败状态通知。 |
| `image_ready(recipe_id, revision, path, texture, info)` | 仅在 PNG 校验和保存成功后通知原配方版本。 |
| `generation_failed(code, message)` | 提交或异步生成失败；不会覆盖原图。 |

默认每 2 秒轮询一次，单次 HTTP 超时为 20 秒，总等待上限为 600 秒，可通过节点属性调整。客户端退出场景树时取消 HTTP、停止定时器并断开内部信号。配方正在编辑时，界面还应更新自己的当前版本或主动 `cancel()`，避免把旧版本图片显示到新版本上。

## 图片保存和校验

完成图片保存到：

```text
user://diy_cocktails/images/<recipe_id>-r<revision>-<task_id>.png
```

每个任务有自己的文件，不会覆盖旧版本。相同任务的重试可复用已保存且字节相同的文件；如果同名文件内容不同，客户端报错并保留原文件。保存时先写临时 `.part`，完成后再改为最终文件名。

客户端只接受提交时同一个服务 origin 下的严格相对任务路径和图片路径，不跟随 HTTP 重定向。JSON 响应上限为 256 KiB，请求体上限为 8 MiB，PNG 下载上限为 16 MiB。客户端在解码前检查 PNG 文件头与尺寸，支持最大 2048 × 2048、总像素不超过 4194304；当前服务默认输出 1024 × 1024。

收到 PNG 后使用 `Image.load_png_from_buffer` 解码，再以 `ImageTexture.create_from_image` 创建纹理。实际图片必须含透明像素和可见内容；文件格式、尺寸、任务身份或写入失败时，只发送失败通知，不把结果应用到原图。客户端没有检查模型是否正确画出每一种原料，因此图片仍应作为待确认成果。

移动设备连接电脑上的开发服务时，需要把 `service_url` 改为可访问的服务地址；手机上的 `127.0.0.1` 指向手机自身。Android 导出还需要启用网络权限。相关 API 见 [Godot HTTPRequest 文档](https://docs.godotengine.org/en/stable/classes/class_httprequest.html)和 [Image 文档](https://docs.godotengine.org/en/stable/classes/class_image.html)。

## 后续接入点

研发页面完成实际配方保存后，再调用本客户端生成该版本的酒图。界面通过 `job_changed` 显示等待状态，收到 `image_ready` 后提供预览和人工确认；确认之后，再由成品数据桥接层把图片路径写到对应配方版本中。主页、研发交互、确认流程和成品数据桥接需在后续任务实现。
