# 原料与器具资料 v1

`catalog.json` 定义 32 项商品：原酒 10、配料 8、装饰品 4、器材 6、杯型 4。独立 `ice` 数组为制作素材，不参与原料库存。

`initial_state.json` 为初始状态模板：原料、装饰库存为零且未点亮；六种器材和四种杯型默认拥有。玩家购买后的状态由唯一 `Supplies` 服务保存到 `user://supplies_state.json`，不修改此模板或商品定义。

商店只有原酒、配料、装饰品，共 22 件可补货商品；`shop_prices.json` 为独立的游戏试用价格。默认器具不售卖，旧存档恢复时会自动补齐，保留材料数量、包装余量和金币。

购买成功和实际消耗后，`Supplies` 将当前总余量同步到 `MenuCatalog.inventory` 并刷新图鉴。配方必需材料及装饰首次买齐后永久点亮，耗尽不退回灰色；当前库存是否足够制作仍单独检查。冰块和可选装饰不参与点亮。

协作对接先看 `docs/物品接口标准.md`；资源与生成说明见 `docs/原料与器具素材接入标准.md`。

图片与完整提示词在 `assets/art/supplies/`，Godot 纹理在该目录的 `textures/`，可操作器材原型场景在 `scenes/supply_assets/`。

来源没有填写的价格和 ABV 保持未知；补货测试采用的草案容量已标记 `game_default_unconfirmed`。鸡尾酒樱桃的含酒状态待核，苦精的 dash 换算仍待确认。
