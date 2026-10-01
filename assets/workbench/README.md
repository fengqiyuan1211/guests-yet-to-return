# 工作台分层美术 · 2026-10-01

当前 v0.3：保留用户确认的第一人称背景 `background.png`，器具、材料、冰与杯型全部通过 `workbench_art.gd` 读取 `assets/art/supplies/textures/*.tres`，与 fengqiyuan 的图鉴／供应品共用同一来源。现有 `tools.png`、`supplies.png` 留作旧版预览资产，运行时不再使用。纸张继续共用 `assets/codex/journal-paper-v1.png`；没有更改公共主题。

以下为 v0.2 原始资产来源与生成提示词。

使用内置 image_gen 生成，参考用户确认的无手第一人称预览以及原游戏暖色西部酒馆画风。没有修改旧游戏美术或主题。

- `background.png`：纯环境与空桌面，含固定油灯和皮垫；没有烘焙交互器具、文字或菜单。
- `tools.png`：透明 RGBA 器具图集，9 个主体：摇壶身、滤盖、顶盖、量酒器、搅拌杯、碟形杯、吧勺、滤冰器、轻压棒。
- `supplies.png`：透明 RGBA 试作材料图集，9 个主体：金酒、朗姆、伏特加、青柠汁、糖浆、苏打、青柠角、方冰、碎冰。
- 旧版 `scripts/workbench_art.gd` 使用经核对的图集区域；新版读取供应品现有 AtlasTexture，不裁改原 PNG 像素。
- `scripts/workbench_table.gd` 负责独立绘制、开合、倾斜、拖拽、填充示意和鼠标命中；准确毫升与状态由 WorkbenchSession 决定。

这些是本分支的试作视觉素材，不冒充供应品标准包，不替换 `data/supplies/catalog.json`，也不授予正式购买或解锁权限。v0.3 已使用标准包的独立高球杯；搅拌杯继续使用自己的独立素材。美术别名只影响显示，不将试作库存迁移为正式库存。

## 最终生成提示词

### background.png

Create a GAME BACKGROUND PLATE by editing the approved attached first-person bartender concept. Preserve its exact first-person downward view, warm painterly western saloon rendering, golden sunset, worn wood bar, dark leather work mat and distant saloon interior. 16:9 landscape. REMOVE ALL text, UI, parchment order, right menu and every tool, glass, bottle, ice bucket and towel from the FOREGROUND counter. Reconstruct the countertop behind them. Keep only the small oil lamp at the far left edge as a fixed environmental prop. The lower 65% is a completely EMPTY richly textured wood counter with a dark leather mat in the middle extending from x=20% to x=75%, y=48% to 91%. Rightmost 22% also empty wood; UI will be added by engine. No hands, no tools, no cups, no bottles on foreground table, no baked shadows of removed objects. Background distant chairs and bottles on far tavern tables may stay. Make empty space usable to later overlay separate interactive tool sprites. Match reference painting precisely, not vector or photoreal photograph.

### tools.png

Create a TRANSPARENT RGBA game sprite atlas matching the attached approved warm hand-painted western bartender scene. Exactly a 3 by 3 equal-cell grid, nine isolated objects, one object per cell, plenty of transparent padding, no background, no checkerboard drawn, no text, no borders, no labels, no shadows beyond each object. View all objects from the same first-person bartender camera looking down ~35 degrees so tops and fronts are visible; warm upper-left lamp light, dark brass and steel with rich painterly highlights, glass visible against transparent background. Each object fits entirely within its own square cell, centered, max 75% cell width or 85% cell height. ROW 1 left: empty open stainless shaker BODY ONLY with no lid. Row1 middle: separate three-piece shaker STRAINER TOP dome only, no small cap. Row1 right: separate small cylindrical shaker CAP only. ROW2 left: upright brass double hourglass JIGGER. Row2 middle: upright empty faceted thick crystal MIXING GLASS. Row2 right: upright EMPTY COUPE stemmed glass. ROW3 left: long twisted BAR SPOON diagonal from upper-left to lower-right. Row3 middle: HAWTHORNE STRAINER diagonal from upper-left to lower-right, coiled spring disc and handle. Row3 right: short WOODEN MUDDLER diagonal. No hand holding anything. High-detail proper game cutout sprites, consistent proportions and camera with attached concept, not tiny icons and not flat vector. Square atlas.

### supplies.png

Create a square TRANSPARENT RGBA sprite atlas matching the reference warm painterly western tavern game. Exactly 3 columns x 3 rows, one isolated object centered in each equal cell, at least 12% clear transparent padding on all sides of each cell. No text, no labels with writing, no frames, no backdrop, no checkerboard drawn. Same perspective as reference bartender tabletop: see front and tops, warm golden light upper left, detailed hand-painted physical objects. Row 1: clear gin bottle with pour spout; amber rum bottle; clear vodka bottle. All three have plain blank parchment labels. Row 2: short bottle of cloudy pale green lime juice with spout; short amber sugar syrup bottle with spout; green-tinted soda siphon. Row 3: fresh lime wedge; cluster of three large clear ice cubes; small heap of crushed ice. Bottles and objects must stay fully inside their own cells with generous transparent gaps. No hands, no shadows outside the objects. Independent game cutouts, not a tabletop scene.

图集实际生成的留白、间距和比例不完全等分，因此运行时使用独立区域定义，不简单按九宫格均切。
