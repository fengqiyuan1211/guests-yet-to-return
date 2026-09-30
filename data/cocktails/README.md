# 五款经典成品酒数据库 · schema v1

正式 JSON 为 `catalog.json`，游戏从这里读取酒款资料；`cocktails.sqlite3` 保存同样的完整记录和可查询明细。运行游戏不需要 SQLite 插件。

接入规范见 [`../../docs/鸡尾酒图鉴接入标准.md`](../../docs/鸡尾酒图鉴接入标准.md)。单条完整结构见 `cocktail_record.example.json`；该例子文件不会自动加载。

## 本轮内容

- A1 遗言、A2 莫吉托、A3 金汤力、A4 长岛冰茶、A5 曼哈顿；B1 回响暂未收录。
- 27 条非冰原料和装饰；5 条冰记录单独放入 `ice`，不属于原料或点亮条件。
- 原表的 22 条制作笔记完整保留，另有 22 条玩家可读的 `display_steps`。
- 每杯新增故事、流程、完整展示工具、墨线装饰 ID 和 `codex_order`；当前卡位使用 2–6，1 号位预留教程酒。
- 图片使用 `res://assets/art/cocktails/<id>.png`，风格提示词同目录 `prompts.json` 与 `prompts.md`。

`alcohol_intensity`、`sweetness`、`sourness`、`bitterness` 是彼此独立的 0–100 游戏感知刻度，不是实际酒精度，也不要求合计 100。莫吉托为原表确认值 40/35/45/0，其余保持原表草案值。

原工作簿的数量、单位、换算、可选标志和行号保持原样。未知字段使用 `null`；曼哈顿苦精 1 dash 的 ml 换算和扣库量未确认，不能写成 0。长岛冰茶柠檬片为可选。冰记录中留存的原库存字段仅用于来源追溯，不进入游戏原料库存。

`equipment` 与 `steps` 保留来源笔记，`display_equipment` 和 `display_steps` 供详情展示。完整展示工具按笔记动作补充，补充依据保存在 `display_equipment_basis`。配方仍为待试调草案，不新增未知操作时长。

`unlock` 保存源表参考：A2 为 true，其余为 null。它不代表玩家解锁，也不决定初始卡片状态。初始玩家状态读取 `../codex_settings.json`，游戏进度另存 `user://menu_state.json`。本轮新游戏五杯均未解锁，原料库存为空。

## 读取接口

`CocktailDatabase.list_cocktails()`、`get_cocktail(id)`、`get_image(id)` 返回酒款定义和图片。图鉴与酒单通过 `MenuCatalog.get_recipe(id)`、`ingredient_progress(recipe)`、`unlocked_recipes()` 结合玩家解锁和库存使用。

## 重建与核对

在工作目录执行 `python3 work/cocktail-database/build_database.py`。也可传 `--source <只读导出JSON>`、`--metadata <展示元数据JSON>`、`--output <输出目录>`。脚本不修改来源文件。

构建源为 `work/store-catalog/source.json` 与当前目录 `codex_metadata.json`。后者保存本轮五杯的展示内容，避免重建时丢失新增字段。手工修改 `catalog.json` 不会反向更新来源或 SQLite。

构建验证 5 款稳定 ID、27 条原料、5 条冰、22 个原步骤、2–6 卡位、分值和来源用量一致，保留可选柠檬片及未知 dash 换算。SQLite 执行完整性、外键和完整 JSON 对照检查。

SQL 明细表包括 `cocktail_ingredients`、`cocktail_ice`、`cocktail_steps`、`cocktail_tags`、`cocktail_equipment`、`cocktail_codex_presentation`、`cocktail_unlock_reference` 及来源表。`record_json` 与正式 JSON 的每杯记录相同，`PRAGMA user_version=1`。
