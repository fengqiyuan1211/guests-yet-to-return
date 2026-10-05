# B 版薄荷素材与接入说明

用户选定「B · 柔和手绘」后制作。`mint-b-leaf.png` 为透明底独立叶片，1024×1536，保留生成文件原始 RGBA；没有覆盖共享仓库原始素材。由内置 imagegen 生成，不使用 CLI。参考为本线程已确认的 B 版概念图。

## 实际使用

- `scripts/workbench_mint.gd` 将叶片放在可轻微弯曲的网格上，随入杯和搅拌运动变形、翻转及漂动。
- 叶片采用杯内轮廓裁剪；裁剪后的纹理坐标保留，避免切边后纹理拉伸。
- 杯中薄荷按前后两组与冰块交错绘制，成品杯玻璃描边最后覆盖；少量酒液色调参与浸湿表现。
- 备料柜、拖动预览、薄荷枝装饰、工作台和成品小窗共用这张叶面素材。
- 纹理开启 mipmap，相关画布采用线性 mipmap 过滤，减少小尺寸显示时的闪烁与噪点。
- 数量、库存、配方和评分沿用制作会话，不由绘制叶片数量反推。当前最多绘制 18 片；实际投入记录保留全部数量。
- 这是 2D 手绘素材与程序动画组合，尚未模拟真实叶片碰撞、折射或浸泡变色。

## 最终生成提示词

内置 imagegen；`transparent_background=true`；输入图为 B 版概念图。

> Extract and redraw the single broad mint leaf on the left of selected B concept into a standalone GAME SPRITE. Only ONE whole fresh spearmint leaf, pointed tip UP, short petiole DOWN, centered upright filling 88% of height; genuine transparent background, NO parchment, glass, text, shadow, frame or other leaves. Match reference B soft hand-painted gouache style, broad ovate fresh green blade, asymmetric saw-tooth edges, pale branching veins, naturally puckered surface in softly blended little green brushstrokes, gentle curled thin edges. Warm soft upper-left light. The sprite should have dimensional botanical form and remain readable at 60px height. Avoid rigid geometric vein grid, plastic, flat cartoon, or photograph. No diagonal overall orientation. Transparent alpha outside the leaf.

## 轻压与破碎状态

`workbench_muddle.gd` 集中定义试玩参数。每片投入的薄荷有独立 `seconds`（有效下压秒数）与 `work`（按鼠标速度估算力度后的累计处理量），存放在该容器的 `mint_processing` 数组中；新加入的叶片从零开始。只认向下的有效移动，提起、横移和静止不计处理时间。推荐约 2–4 秒是试玩提示，强度越大，形变越快；约 3–9 处理量逐渐从破边发展为明显碎片，并非真实测量值。

叶面先略微压扁、加深湿润色，再沿不规则网格逐渐撕开、分离并漂动。渲染插值让小段动作提交后的变化平滑；碎片只属于原叶的显示，不会增加材料数量。普通互倒按转移叶数带走对应状态，过滤保留源容器里的叶片，倒空清除该容器的状态。单杯结果快照、重试幂等和退出恢复使用同一组数据。旧存档没有细分处理字段时兼容读取为完整叶片，不凭缺失记录猜测破碎度。

轻压专用提示位于现有浅底深字操作面板，显示有效时长、力度、处理进度、可停手及偏碎提示。新旧叶片同时存在时提示已有叶片偏碎，避免把旧叶视为新叶。品质评分仍沿用原有的草本处理判定，本次没有凭视觉碎片数量新增苦度或过度轻压扣分；这部分可另行确定数值后接入。

回归：`python3 tests/run_workbench_muddle.py --godot /path/to/Godot --graphics`，使用独立 `/tmp` 存档，覆盖原生上下拖动、声音、停手、鲜叶加入、过滤/互倒、写盘失败、重复动作、成品快照及新进程恢复。

### 2026-10-05：棒柄抓取

从器具柜按住轻压棒拖进打开的容器后，可以不松手继续上下拉动。松手时棒子留在杯中，再次按住露出的棒柄即可继续；杯口本身不再代替棒柄触发轻压。棒身随上下位移移动，旁侧标尺显示行程，提示栏同步显示深度、力度与有效时长。只记录实际向下移动的行程，到底继续下拖不累计；上提、静止、水平移动不处理薄荷。工具拖到弃液槽不会倒空其所在的杯子。

棒子位置为当前页面的交互状态，重新打开页面需要重新取工具；薄荷处理状态与单杯记录仍按原机制保存。这次没有修改评分参数、库存或配方。
