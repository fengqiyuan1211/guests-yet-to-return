# A2 横向青绿桌旗接入说明
日期：2026-10-19

已按确认的 A2 方案接入 Godot 主酒馆。B 酒红皮革方案保留在概念预览目录，未启用。

## 实现
- 新素材：assets/pixel_b/saloon_depth/saloon-teal-runner.png。使用内置 imagegen，完整提示词及来源在同目录 teal-runner-generation.json。
- saloon_composition.gd 增加 COUNTER_TEXTURE_PATH；saloon_counter.gd 仅取新素材 y=544 以下的台面区域。
- 大厅原背景、人物坐标、前景遮挡位置均保留。桌旗位于人物前、对话框后，自然遮住下半身并被界面遮挡。
- 台面沿用大厅 ShaderMaterial，昼夜同步；不接收鼠标事件。
- 小线、黄色生物立绘未改，工作台及业务逻辑未改。
- 修改前脚本备份：/Users/wit/Documents/ChatGPT/酒馆模拟器/备份/横向桌旗接入前-20261019/

## 验证
- Godot 资源导入成功；git diff --check 通过。
- 有图形渲染检查：28 项通过，0 项失败。包含五位角色遮挡、日夜材质、不同窗口比例、商店往返保留对话。
- 无窗口检查：23 项通过。
- 已查看艾达日夜及 4:3 截图，未发现台面接缝和人物穿透。
- 一次图形截图运行超时，重跑完整通过。最终运行退出仍有 ObjectDB/resource 清理警告，见 verification.log；没有 GDScript 报错。此前测试已有同类退出警告，本次未扩展修复。
- 测试使用独立存档及 Dummy 音频，不修改玩家存档或声音设置。
