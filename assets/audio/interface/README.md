# 界面与商店音效

本批为项目内程序合成的短拟音，不是真实商品的现场录音。22.05 kHz / 16-bit / mono，无外部采样。
普通按钮：木质轻击。瓶装液体：玻璃共鸣加轻晃声；叶片：柔软摩擦；果料：柔和落台；砂糖：细颗粒；杯具：玻璃；器具：金属。`purchase-*` 在各自材质声后加入短金币确认声，仅在购买事务成功后触发。
全部接入 SFX 总线；不影响存档或商品价格。

接入：`SaloonAudio.ui` 监听新增 BaseButton 的 pressed 信号；商店货品与购买按钮设置 `custom_audio=true`，改由商品选择与成功购买回调触发，不叠加普通按钮声。禁用按钮无声，失焦停止当前声音并拒绝新声音。商品类型依据目录 SKU / category 映射，供未来替换实录音效。

场景 BGM：SaloonAudio.acquire_scene(owner, context)，当前支持 shop / research / workbench。后打开的场景覆盖前一场景，节点退出自动释放，商店覆盖工作台时返回可恢复工作台曲目。无人占用时恢复大厅曲目；期间跨昼夜则改用对应大厅时段。共用双播放器 3.5 秒渐变与 Music 音量。配乐原始文件及许可见 ../music/credits.json。

验证场景：`tests/verify_scene_feedback.tscn`，必须传隔离的 slot-wallet / dialogue-save / game-save / menu-save / supplies-save / workbench-save / audio-settings 路径（/tmp），覆盖原生按钮点击、分类商品音效、成功及失败事务、场景退出与商店覆盖、静音、失焦及音频解码。
