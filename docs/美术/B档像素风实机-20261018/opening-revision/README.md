# 序章画面统一与长按快进
日期：2026-10-19。已接入 Godot，图片为独立存档实机截图。

## 画面
1. 三年前的城市酒吧：两位短发男性背影，仍不露正脸。只替换 city-bar-faceless.tres 的中右图块来源，旧图集与其他回忆图块保留。
2. 现经营酒馆的大厅、序章/开业前室内 CG、新手教程及正常/自由/研发工作台，通过 Pixel.texture 与 SaloonComposition 统一使用 saloon-teal-runner.png。旧金柱围挡不再由这些入口加载。城市回忆与门廊是不同地点，保留各自背景。
3. 开业前成品鸡尾酒预览框从 340×415 改为 240×270；杯脚落在设计坐标 y=590（台面边沿约 y=520），并加入低对比接触阴影。
4. 酒液仍使用实际教学杯的结果数据绘制，没有将成品改成固定图片。阴影为单独开关，不改变图鉴/评价弹窗。
5. 小线及黄色生物立绘未改。

## 快进
- 序章与开业前剧情：短按空格在松开时推进一次；点击继续行为保持。
- 持续按住约 0.35 秒后，以 3 倍速度显示文字、缩短自动阅读等待，并加速 CG 背景动画/淡入。
- 即使自动播放关闭，按住也能连续播放普通对白；松开后不额外跳一行，也不改变原自动播放开关。
- 邮件、选项、教学入口、签收、递水、备料购物、开门等交互等待手动操作，长按松开不会提交。
- 历史/邮件弹窗及窗口失焦取消长按状态，防止回到游戏后继续跳剧情。
- 不修改 Engine.time_scale，不加速经营时间、工作台动作或音乐。

## 资源与实现
- 内置 imagegen 图像编辑：assets/pixel_b/opening_revision/two-men-story.png。
- 完整提示词与原始来源：assets/pixel_b/opening_revision/generation.json。
- 共用背景：assets/pixel_b/saloon_depth/saloon-teal-runner.png。
- 快进状态：scripts/story_fast_forward.gd；阅读等待：scripts/story_autoplay.gd。
- 接入：scripts/opening_story.gd、opening_departure.gd、opening_background.gd。
- 资源路由：scripts/pixel_art.gd、saloon_composition.gd、assets/pixel_b/scenes/saloon.tres。
- 杯脚阴影：scripts/workbench_drink_preview.gd 的 tabletop_shadow 开关。
- 修改前备份：/Users/wit/Documents/ChatGPT/酒馆模拟器/备份/序章画面与快进修改前-20261019/

## 验证
- Godot 导入与 git diff --check 通过。
- 序章/教程回归：336 + 63 项通过；旧档保护、初次启动退出后恢复检查通过。
- 开业衔接：35 + 58 + 5 项通过。
- 最新图形专项：34 项通过，0 失败。包含实际按键分发、短按/长按/重复键/松开、文字速度、持续推进、交互阻断、背景路由、酒杯落点和截图。
- 测试使用独立临时存档。可视化示例杯为测试构造数据，不改玩家存档。
- 首轮图形捕获曾等待渲染超时；专项捕获改用 force_draw 后完成。一次键盘速度断言因测试窗口未获得焦点失败，显式获取焦点后完整重跑通过。
- 最终退出仍有 ObjectDB / resources 清理警告（此前已有同类记录），无 GDScript 错误；详见日志。本次没有扩展修复资源生命周期。

若游戏窗口在更新前就已打开，保存并重启该运行实例后查看，避免旧材质缓存影响显示。
