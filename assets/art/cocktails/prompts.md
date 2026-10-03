# 鸡尾酒成品图提示词

风格编号：`saloon-cocktail-cutout-v1`。本轮使用内置 image_gen 生成，启用透明背景。

## 后续生成方法

沿用下面的通用模板，只替换酒名、杯型、酒液、冰和装饰。保持 2D 手绘水彩与水粉质感、暖色侧光、完整杯身、透明底和无文字。成品杯中是否留冰、使用何种装饰，以酒谱为准。

仅靠提示词无法保证每次完全一致；新图生成时可附上本目录中的一张已确认成品图作为风格参考。透明背景需要同时在图像工具中启用，不能只靠文字要求。

## 通用模板

```text
Use case: stylized-concept. Asset type: individual finished cocktail illustration for a 2D western saloon game's parchment recipe journal and menu. Primary request: draw exactly ONE physically plausible {cocktail_name}, with {glass_shape}, {liquid_description}, {ice_description}, and {garnish_description}. Style/medium: refined hand-painted gouache and watercolor game item illustration, semi-realistic proportions, subtle natural paper-like brush texture INSIDE the painted object only, delicate warm dark-brown contour accents, restrained amber highlights, believable transparent glass, clearly readable silhouette. Composition: square canvas, full glass and entire stem/base and garnish visible, centered with generous clean 12 percent margins, slight elevated three-quarter front view that shows the rim ellipse and drink surface. Lighting: soft warm saloon light from upper left, subtle cool glass reflections, preserve the drink's true color. Backdrop: genuinely transparent alpha outside the object and through unpainted glass areas; no backdrop, no paper card, no tabletop, no cast floor shadow. Constraints: accurate finished serving presentation, no ingredients placed outside glass, no bottles, no bartending tools, no humans, no hats, no frame, no lettering, no labels, no logo, no watermark; no pixel art, no shiny 3D render, no comic face, no exaggerated fantasy shapes. Output: a crisp square transparent PNG suitable for small in-game catalogue cards.
```

## 五款酒的实际提示词

### 遗言 / Last Word

图片：`last_word.png`。

```text
Use case: stylized-concept. Asset type: individual finished cocktail illustration for a 2D western saloon game's parchment recipe journal and menu. Primary request: draw exactly ONE physically plausible Last Word, with a delicate thin-stemmed classic coupe cocktail glass with a shallow rounded bowl, short-medium stem and circular foot, a softly cloudy pale jade-green cocktail, subtle grey-green citrus hue, NOT luminous neon green, filled just below the rim, NO ice remaining in the serving glass; this is shaken with ice and strained, and NO garnish, matching this game's source recipe. Style/medium: refined hand-painted gouache and watercolor game item illustration, semi-realistic proportions, subtle natural paper-like brush texture INSIDE the painted object only, delicate warm dark-brown contour accents, restrained amber highlights, believable transparent glass, clearly readable silhouette. Composition: square canvas, full glass and entire stem/base and garnish visible, centered with generous clean 12 percent margins, slight elevated three-quarter front view that shows the rim ellipse and drink surface. Lighting: soft warm saloon light from upper left, subtle cool glass reflections, preserve the drink's true color. Backdrop: genuinely transparent alpha outside the object and through unpainted glass areas; no backdrop, no paper card, no tabletop, no cast floor shadow. Constraints: accurate finished serving presentation, no ingredients placed outside glass, no bottles, no bartending tools, no humans, no hats, no frame, no lettering, no labels, no logo, no watermark; no pixel art, no shiny 3D render, no comic face, no exaggerated fantasy shapes. Output: a crisp square transparent PNG suitable for small in-game catalogue cards.
```

### 莫吉托 / Mojito

图片：`mojito.png`。

```text
Use case: stylized-concept. Asset type: individual finished cocktail illustration for a 2D western saloon game's parchment recipe journal and menu. Primary request: draw exactly ONE physically plausible Mojito, with a tall straight-sided transparent highball glass with a solid clear base and realistic proportions, a nearly colorless faintly pale yellow-green sparkling drink, with a few lightly pressed green mint leaves naturally dispersed mainly in the lower part and delicate soda bubbles, clear-white crushed ice loosely filling the highball, irregular small fragments, NOT large square cubes, and exactly one fresh mint sprig protruding at the rim and exactly one lime wedge resting on the rim; no extra whole lime slices submerged because this recipe uses lime juice. Style/medium: refined hand-painted gouache and watercolor game item illustration, semi-realistic proportions, subtle natural paper-like brush texture INSIDE the painted object only, delicate warm dark-brown contour accents, restrained amber highlights, believable transparent glass, clearly readable silhouette. Composition: square canvas, full glass and entire stem/base and garnish visible, centered with generous clean 12 percent margins, slight elevated three-quarter front view that shows the rim ellipse and drink surface. Lighting: soft warm saloon light from upper left, subtle cool glass reflections, preserve the drink's true color. Backdrop: genuinely transparent alpha outside the object and through unpainted glass areas; no backdrop, no paper card, no tabletop, no cast floor shadow. Constraints: accurate finished serving presentation, no ingredients placed outside glass, no bottles, no bartending tools, no humans, no hats, no frame, no lettering, no labels, no logo, no watermark; no pixel art, no shiny 3D render, no comic face, no exaggerated fantasy shapes. Output: a crisp square transparent PNG suitable for small in-game catalogue cards.
```

### 金汤力 / Gin and Tonic

图片：`gin_and_tonic.png`。

```text
Use case: stylized-concept. Asset type: individual finished cocktail illustration for a 2D western saloon game's parchment recipe journal and menu. Primary request: draw exactly ONE physically plausible Gin and Tonic, with a tall straight-sided transparent highball glass, no stem, with a sturdy clear flat base, a truly clear colorless sparkling liquid with delicate tonic bubbles, NOT green or amber liquid, several transparent standard cubed ice pieces floating naturally in the glass, and exactly one green lime wedge on the rim; no mint, no rosemary, no lemon wheel, no straw. Style/medium: refined hand-painted gouache and watercolor game item illustration, semi-realistic proportions, subtle natural paper-like brush texture INSIDE the painted object only, delicate warm dark-brown contour accents, restrained amber highlights, believable transparent glass, clearly readable silhouette. Composition: square canvas, full glass and entire stem/base and garnish visible, centered with generous clean 12 percent margins, slight elevated three-quarter front view that shows the rim ellipse and drink surface. Lighting: soft warm saloon light from upper left, subtle cool glass reflections, preserve the drink's true color. Backdrop: genuinely transparent alpha outside the object and through unpainted glass areas; no backdrop, no paper card, no tabletop, no cast floor shadow. Constraints: accurate finished serving presentation, no ingredients placed outside glass, no bottles, no bartending tools, no humans, no hats, no frame, no lettering, no labels, no logo, no watermark; no pixel art, no shiny 3D render, no comic face, no exaggerated fantasy shapes. Output: a crisp square transparent PNG suitable for small in-game catalogue cards.
```

### 长岛冰茶 / Long Island Iced Tea

图片：`long_island_iced_tea.png`。

```text
Use case: stylized-concept. Asset type: individual finished cocktail illustration for a 2D western saloon game's parchment recipe journal and menu. Primary request: draw exactly ONE physically plausible Long Island Iced Tea, with a tall straight-sided transparent highball glass with a sturdy clear base and realistic proportions, a translucent warm amber-brown cola-and-citrus drink with a subtle lighter gold upper area and tiny bubbles, visually like light iced tea but not opaque black cola, several clear standard square ice cubes in the finished drink, and exactly one thin yellow lemon slice on the rim, shown as this recipe's optional garnish; no mint, no cherry, no straw. Style/medium: refined hand-painted gouache and watercolor game item illustration, semi-realistic proportions, subtle natural paper-like brush texture INSIDE the painted object only, delicate warm dark-brown contour accents, restrained amber highlights, believable transparent glass, clearly readable silhouette. Composition: square canvas, full glass and entire stem/base and garnish visible, centered with generous clean 12 percent margins, slight elevated three-quarter front view that shows the rim ellipse and drink surface. Lighting: soft warm saloon light from upper left, subtle cool glass reflections, preserve the drink's true color. Backdrop: genuinely transparent alpha outside the object and through unpainted glass areas; no backdrop, no paper card, no tabletop, no cast floor shadow. Constraints: accurate finished serving presentation, no ingredients placed outside glass, no bottles, no bartending tools, no humans, no hats, no frame, no lettering, no labels, no logo, no watermark; no pixel art, no shiny 3D render, no comic face, no exaggerated fantasy shapes. Output: a crisp square transparent PNG suitable for small in-game catalogue cards.
```

### 曼哈顿 / Manhattan

图片：`manhattan.png`。

```text
Use case: stylized-concept. Asset type: individual finished cocktail illustration for a 2D western saloon game's parchment recipe journal and menu. Primary request: draw exactly ONE physically plausible Manhattan, with a delicate thin-stemmed classic coupe cocktail glass with a shallow rounded bowl, short-medium stem and circular foot, matching the Last Word glass proportions, a clear rich reddish amber-brown whiskey-and-vermouth cocktail, warm deep ruby highlights, filled just below the rim, NO ice remaining in the serving glass; this is stirred with ice and strained, and exactly one dark red cocktail cherry resting visibly near the inner rim in the drink; no orange peel, no lemon, no mint, no garnish pick. Style/medium: refined hand-painted gouache and watercolor game item illustration, semi-realistic proportions, subtle natural paper-like brush texture INSIDE the painted object only, delicate warm dark-brown contour accents, restrained amber highlights, believable transparent glass, clearly readable silhouette. Composition: square canvas, full glass and entire stem/base and garnish visible, centered with generous clean 12 percent margins, slight elevated three-quarter front view that shows the rim ellipse and drink surface. Lighting: soft warm saloon light from upper left, subtle cool glass reflections, preserve the drink's true color. Backdrop: genuinely transparent alpha outside the object and through unpainted glass areas; no backdrop, no paper card, no tabletop, no cast floor shadow. Constraints: accurate finished serving presentation, no ingredients placed outside glass, no bottles, no bartending tools, no humans, no hats, no frame, no lettering, no labels, no logo, no watermark; no pixel art, no shiny 3D render, no comic face, no exaggerated fantasy shapes. Output: a crisp square transparent PNG suitable for small in-game catalogue cards.
```

