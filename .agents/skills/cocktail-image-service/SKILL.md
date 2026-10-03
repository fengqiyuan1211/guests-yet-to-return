---
name: cocktail-image-service
description: 维护本仓库的 DIY 鸡尾酒图片生成服务、配方视觉规则和 Godot 接入时使用。适用于接口、提示词、参考配置和生成结果接入，不用于一般图片创作。
---

# DIY 鸡尾酒图片服务

本 skill 是开发维护指南，游戏运行不依赖 skill 文件。运行入口是独立 HTTP 服务，Godot 通过客户端提交配方、轮询和下载图片。

## 按任务读取

以下相对路径均从本 skill 目录向上三层回到 `godot-home`：

- 启动、配置、接口和测试：[服务 README](../../../services/cocktail-image-service/README.md)。先读与当前任务相关的章节。
- 调整经典示例选择：[few_shots.json](../../../services/cocktail-image-service/config/few_shots.json)。示例配方、外观描述和冻结成品图共同提供 few-shot 参考。
- 增加原料的视觉依据：[visual_profiles.json](../../../services/cocktail-image-service/config/visual_profiles.json)。核对 SKU、颜色、透明度和固体特征。
- 编写真实请求：[request-gin-tonic.json](../../../services/cocktail-image-service/examples/request-gin-tonic.json)。以现有数据字段为准，避免重复发明协议。
- 接入研发和成品数据：[Godot 接入说明](../../../docs/DIY酒图自动生成服务.md)及 [diy_image_client.gd](../../../scripts/diy_image_client.gd)。

## 视觉约束

- 每次生成都重新绘制成品杯、酒液、冰和实际装饰；不能直接把粗预览当最终酒图，也不能把预览轮廓作为不可变的遮罩。
- `preview_image` 只作颜色和液面参考。`recipe.story` 只提供有限氛围，不能改变原料、酒液颜色、杯型、冰或装饰，不能添加文字、商标、背景场景或无关道具。
- 实际 `recipe` 是事实依据。酒名、故事、few-shot 经典名称不能触发额外的经典配方或未加入的水果装饰。
- 冻结的五杯经典参考提供画风依据，维护服务时保留它们；不能用参考配方替换当前 DIY 配方，也不能在普通生成任务中改写参考图片或经典数据。
- 冰单独写入 `recipe.ice`，区分制作冰与出品冰。只绘出最终留在杯中的冰、装饰和 `retained_solids`；过滤掉的固体不留杯。未知 dash 用量不擅自换算为 ml。

## 服务维护与接入

- 模型密钥只在服务端配置，不写进 Godot、请求示例或仓库。Godot 的可选 `service_token` 只是服务访问凭据。
- 保留 `request_id` 幂等语义和配方 `id/revision/hash` 绑定。修改实际配方、杯型、制作方法或故事后增加版本；旧任务不能更新新版本图片。
- 不自动重试付费提交。超时或响应丢失时，先查询已知任务及本地记录；状态不明时报告，不通过不断换 `request_id` 触发重复生成。新增付费生成应符合当前用户授权。
- Godot 只下载同一服务的相对资源路径，保留禁重定向、PNG 大小/尺寸/透明度校验、取消旧请求、退出场景清理和失败保留原图的行为。
- 在研发页面接入时，先保存真实配方，再生成该版本酒图；显示进度和待确认预览，经确认后才由成品数据桥接层保存对应图片引用。不要把修改服务视为已经接入研发 UI。

## 验证与复现

使用 README 中的离线提示词和模拟 provider 测试，验证数据约束、任务幂等、版本绑定与图片保存；涉及 Godot 时使用隔离临时项目和临时存档。真实模型生成按当前授权执行。

JSON 通过校验只说明结构和数据约束成立，PNG 通过校验只说明格式、尺寸和透明度成立；两者都不证明图片正确呈现配方。保留 `needs_review` 和 `semantic_validation` 的真实状态，人工对照杯型、酒液颜色、留杯冰、实际装饰和整体画风。

维护生成记录中的实际 few-shot 选择及参考版本、最终 prompt、配方与请求 hash、实际提交的 seed、模型和 provider、任务编号与结果路径。未返回的模型版本等信息不虚构；相同 seed 也不保证不同模型版本生成完全一致的图片。
