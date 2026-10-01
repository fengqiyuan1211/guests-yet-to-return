# 原料与器具资料 v1

`catalog.json` 定义 32 项商品：原酒 10、配料 8、装饰品 4、器材 6、杯型 4。独立 `ice` 数组为制作素材，不参与原料库存。

`initial_state.json` 为全零、未解锁的初始状态模板。玩家购买后的状态通过 `SupplyInventory` 保存，不修改此模板或商品定义。

协作对接先看 `docs/物品接口标准.md`；资源与生成说明见 `docs/原料与器具素材接入标准.md`。

图片与完整提示词在 `assets/art/supplies/`，Godot 纹理在该目录的 `textures/`，可操作器材原型场景在 `scenes/supply_assets/`。

来源没有填写的价格和 ABV 保持未知；补货测试采用的草案容量已标记 `game_default_unconfirmed`。鸡尾酒樱桃的含酒状态待核，苦精的 dash 换算仍待确认。
