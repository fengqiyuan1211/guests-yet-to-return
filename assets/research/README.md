# 研发书桌背景

`research-desk-v1.png`：2026-10-04 使用内置 imagegen 生成，依据用户选择的 C 入口方向。原图为 1672 × 941，由 Godot 按 1600 × 900 场景坐标缩放；文字、按钮和物件交互区域均由 Godot 绘制，未烘焙在图片中。

参考：本工作线生成的 C「研发书桌」概念图上半部分，仅用作美术与空间构图参考。当前资源为固定暖色傍晚场景；现有制作工作台的时段背景仍使用原同步系统。

生成方式：内置 image_gen；无 CLI/API 调用。原始生成图保留在 Codex generated_images 目录，项目运行直接引用本目录图片。

## 本次生成提示词

```text
Use case: ui-mockup / illustration-story game environment asset. Use ONLY the upper scene of reference image as art-direction reference. Create ONE production background image for the existing Chinese 2D saloon cocktail game research screen, landscape 16:9, 1920x1080. Not a concept sheet, not a collage. Full bleed scene, no border. First-person looking down at a beautiful physical dark walnut research desk in a Western seaport saloon, amber oil lantern left, soft sea sunset window and subtle out-of-focus saloon in uppermost background. Match reference warm hand-painted illustrated wood, leather, paper, brass; detailed tactile watercolor/gouache realism, no hands/people.
Precise composition for overlaying real Godot controls: a large open leather notebook occupies normalized x .14-.58, y .28-.87; notebook RIGHT page faces camera mostly square, nearly horizontal text lines, clean blank pale cream area x .36-.56,y .42-.72. Left page has a delicate sepia line sketch of a highball cocktail and botanical leaf, NO lettering. To the right a closed dark leather legendary manuscript sits x .63-.90,y .22-.49 with a large EMPTY light cream paper label centered at x .67-.86,y .30-.42. Below manuscript a wooden index-card drawer occupies x .65-.88,y .57-.84, front face turned toward camera with big EMPTY cream label x .68-.85,y .68-.78, several blank recipe cards visibly protruding. Small elegant pencil near lower edge; modest highball with translucent golden-green liquid at far right .93,.60; warm lit oil lantern far left. Keep lower center clear wood for a resume-session overlay. Keep upper left and upper right relatively uncluttered/dark for navigation overlays. Strong coherent focal light on notebook paper. Desktop fills almost all image; background only top quarter. Beautiful but usable, avoid excessive decorative clutter.
ABSOLUTELY NO text, NO letters, numbers, logo, watermarks, menus, UI buttons, HUD, annotations, frames or captions anywhere. Empty labels must be genuinely blank. Preserve separated three interactable objects notebook/book/drawer so hover borders and real text can be overlaid later.
```
