# 鸡尾酒成品图提示词

风格编号：`saloon-cocktail-cutout-v1`。当前画风修订：`handdrawn-watercolor-20261004`。

## 后续生成方法

以本目录已确认酒图作为风格参考，启用透明背景；保持柔和水彩色块、细墨线和轻微铅笔纹理。只画完整的酒杯、酒液和配方装饰，名称、纸张、角花由游戏界面绘制。

酒款 ID、图片路径、配方和库存规则沿用原接口。新酒替换杯型、酒液、出品冰和装饰字段，制作冰不会留在成品图中。金汤力使用高球杯。

## 通用模板

```text
Use case: stylized-concept. Create exactly one {cocktail_name} cocktail illustration for a 2D western saloon parchment journal. Depict {glass_shape}, {liquid_description}, {ice_description}, {garnish_description}. Style: charming hand-drawn cafe sketchbook illustration, delicate slightly wobbly dark warm-grey pen contours, restrained overlapping sketch lines, soft translucent watercolor washes, light colored-pencil grain inside painted regions, gentle fresh inviting colors, airy simplified forms. Match the approved five cocktail illustrations in this directory as style references. Keep the complete glass, entire stem/base and garnish visible, square canvas, slightly elevated three-quarter view and comfortable margins. Genuine transparent alpha background, no paper, no lettering, no underline, no external ground shadow, no frame, no extra ingredients outside the glass, no shiny 3D rendering.
```

### 遗言 / Last Word

图片：`last_word.png`。

```text
Use case: stylized-concept. Create exactly one Last Word cocktail illustration for a 2D western saloon parchment journal. Depict a delicate thin-stemmed classic coupe cocktail glass with a shallow rounded bowl, short-medium stem and circular foot, a softly cloudy pale jade-green cocktail, subtle grey-green citrus hue, NOT luminous neon green, filled just below the rim, NO ice remaining in the serving glass; this is shaken with ice and strained, NO garnish, matching this game's source recipe. Style: charming hand-drawn cafe sketchbook illustration, delicate slightly wobbly dark warm-grey pen contours, restrained overlapping sketch lines, soft translucent watercolor washes, light colored-pencil grain inside painted regions, gentle fresh inviting colors, airy simplified forms. Match the approved five cocktail illustrations in this directory as style references. Keep the complete glass, entire stem/base and garnish visible, square canvas, slightly elevated three-quarter view and comfortable margins. Genuine transparent alpha background, no paper, no lettering, no underline, no external ground shadow, no frame, no extra ingredients outside the glass, no shiny 3D rendering.
```

### 莫吉托 / Mojito

图片：`mojito.png`。

```text
Use case: stylized-concept. Create exactly one Mojito cocktail illustration for a 2D western saloon parchment journal. Depict a tall straight-sided transparent highball glass with a solid clear base and realistic proportions, a nearly colorless faintly pale yellow-green sparkling drink, with a few lightly pressed green mint leaves naturally dispersed mainly in the lower part and delicate soda bubbles, clear-white crushed ice loosely filling the highball, irregular small fragments, NOT large square cubes, exactly one fresh mint sprig protruding at the rim and exactly one lime wedge resting on the rim; no extra whole lime slices submerged because this recipe uses lime juice. Style: charming hand-drawn cafe sketchbook illustration, delicate slightly wobbly dark warm-grey pen contours, restrained overlapping sketch lines, soft translucent watercolor washes, light colored-pencil grain inside painted regions, gentle fresh inviting colors, airy simplified forms. Match the approved five cocktail illustrations in this directory as style references. Keep the complete glass, entire stem/base and garnish visible, square canvas, slightly elevated three-quarter view and comfortable margins. Genuine transparent alpha background, no paper, no lettering, no underline, no external ground shadow, no frame, no extra ingredients outside the glass, no shiny 3D rendering.
```

### 金汤力 / Gin and Tonic

图片：`gin_and_tonic.png`。

```text
Use case: stylized-concept. Create exactly one Gin and Tonic cocktail illustration for a 2D western saloon parchment journal. Depict a tall straight-sided transparent highball glass, no stem, with a sturdy clear flat base, a truly clear colorless sparkling liquid with delicate tonic bubbles, NOT green or amber liquid, several transparent standard cubed ice pieces floating naturally in the glass, exactly one green lime wedge on the rim; no mint, no rosemary, no lemon wheel, no straw. Style: charming hand-drawn cafe sketchbook illustration, delicate slightly wobbly dark warm-grey pen contours, restrained overlapping sketch lines, soft translucent watercolor washes, light colored-pencil grain inside painted regions, gentle fresh inviting colors, airy simplified forms. Match the approved five cocktail illustrations in this directory as style references. Keep the complete glass, entire stem/base and garnish visible, square canvas, slightly elevated three-quarter view and comfortable margins. Genuine transparent alpha background, no paper, no lettering, no underline, no external ground shadow, no frame, no extra ingredients outside the glass, no shiny 3D rendering.
```

### 长岛冰茶 / Long Island Iced Tea

图片：`long_island_iced_tea.png`。

```text
Use case: stylized-concept. Create exactly one Long Island Iced Tea cocktail illustration for a 2D western saloon parchment journal. Depict a tall straight-sided transparent highball glass with a sturdy clear base and realistic proportions, a translucent warm amber-brown cola-and-citrus drink with a subtle lighter gold upper area and tiny bubbles, visually like light iced tea but not opaque black cola, several clear standard square ice cubes in the finished drink, exactly one thin yellow lemon slice on the rim, shown as this recipe's optional garnish; no mint, no cherry, no straw. Style: charming hand-drawn cafe sketchbook illustration, delicate slightly wobbly dark warm-grey pen contours, restrained overlapping sketch lines, soft translucent watercolor washes, light colored-pencil grain inside painted regions, gentle fresh inviting colors, airy simplified forms. Match the approved five cocktail illustrations in this directory as style references. Keep the complete glass, entire stem/base and garnish visible, square canvas, slightly elevated three-quarter view and comfortable margins. Genuine transparent alpha background, no paper, no lettering, no underline, no external ground shadow, no frame, no extra ingredients outside the glass, no shiny 3D rendering.
```

### 曼哈顿 / Manhattan

图片：`manhattan.png`。

```text
Use case: stylized-concept. Create exactly one Manhattan cocktail illustration for a 2D western saloon parchment journal. Depict a delicate thin-stemmed classic coupe cocktail glass with a shallow rounded bowl, short-medium stem and circular foot, matching the Last Word glass proportions, a clear rich reddish amber-brown whiskey-and-vermouth cocktail, warm deep ruby highlights, filled just below the rim, NO ice remaining in the serving glass; this is stirred with ice and strained, exactly one dark red cocktail cherry resting visibly near the inner rim in the drink; no orange peel, no lemon, no mint, no garnish pick. Style: charming hand-drawn cafe sketchbook illustration, delicate slightly wobbly dark warm-grey pen contours, restrained overlapping sketch lines, soft translucent watercolor washes, light colored-pencil grain inside painted regions, gentle fresh inviting colors, airy simplified forms. Match the approved five cocktail illustrations in this directory as style references. Keep the complete glass, entire stem/base and garnish visible, square canvas, slightly elevated three-quarter view and comfortable margins. Genuine transparent alpha background, no paper, no lettering, no underline, no external ground shadow, no frame, no extra ingredients outside the glass, no shiny 3D rendering.
```

## 本轮去底提示词

```text
Background-removal edit only. Extract the cocktail illustration from the supplied image onto a true transparent alpha background. Preserve the original illustrated cocktail EXACTLY: same delicate sketch lines, watercolor texture, restrained color saturation, glass shape, scale, all highlights, ice, garnish and original gentle pen-and-watercolor style. Do not redesign, redraw, simplify, enhance sketchiness, intensify color or alter proportions. Remove the cream paper background completely, ALL handwritten English lettering and underlines, and the scribbled ground shadow outside the glass. Keep only the full cocktail glass and attached garnish. Do not erase the pale painted highlights or ice inside the object. Keep the complete object at the same position and size within the original square canvas, all edges unclipped. True transparent PNG, no white or cream rectangle, no baked checkerboard, no halos, no text. This is asset isolation, not a new stylistic rendering.
```
