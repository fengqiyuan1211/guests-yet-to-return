extends Control
## The same detail layout renders every cocktail directly from its JSON definition.
signal back_requested

const INK := Color("493019")
const MUTED := Color("674b2c")
const SCORE := preload("res://scripts/journal_score.gd")
const DIVIDER := preload("res://scripts/journal_divider.gd")
const INK_BUTTON := preload("res://scripts/journal_ink_button.gd")
const TOOL_ICONS := {
	"量酒器": "jigger", "轻压棒": "muddler", "吧勺": "bar_spoon",
	"摇壶": "shaker", "滤器": "strainer", "调酒杯": "mixing_glass",
	"高球杯": "highball", "鸡尾酒杯": "coupe", "冷却鸡尾酒杯": "coupe", "球形杯": "balloon"
}
var recipe: Dictionary = {}
var paper: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background()
	_header()
	_left_column()
	_ingredients_column()
	_story_column()

func _label(parent: Node, rect: Rect2, value: String, font_size := 19, color := INK, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	if font_size >= 22:
		label.add_theme_font_override("font", get_theme_font("font", "Button"))
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _rule(parent: Node, rect: Rect2) -> void:
	var line := Control.new()
	line.set_script(DIVIDER)
	line.position = rect.position
	line.size = rect.size
	parent.add_child(line)

func _texture(parent: Node, rect: Rect2, texture: Texture2D, stretch := TextureRect.STRETCH_KEEP_ASPECT_CENTERED) -> void:
	if texture == null:
		return
	var picture := TextureRect.new()
	picture.position = rect.position
	picture.size = rect.size
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = stretch
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)

func _background() -> void:
	# Paper fills the complete three-column page; artwork keeps its own aspect ratio.
	_texture(self, Rect2(Vector2.ZERO, size), paper, TextureRect.STRETCH_SCALE)
	_rule(self, Rect2(134, 100, 1040, 6))
	for x in [465, 844]:
		var line := ColorRect.new()
		line.position = Vector2(x, 119)
		line.size = Vector2(1, 535)
		line.color = Color(0.39, 0.25, 0.12, 0.22)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)

func _header() -> void:
	var back := Button.new()
	back.set_script(INK_BUTTON)
	back.name = "BackToCodex"
	back.position = Vector2(136, 23)
	back.size = Vector2(159, 44)
	back.text = "‹ 返回图鉴"
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.add_theme_font_size_override("font_size", 21)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		back.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		back.add_theme_color_override(state, INK)
	back.pressed.connect(func(): back_requested.emit())
	add_child(back)
	var title := _label(self, Rect2(425, 15, 485, 55), str(recipe.name), 39, INK, HORIZONTAL_ALIGNMENT_CENTER)
	title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	title.name = "RecipeTitle"
	_label(self, Rect2(420, 69, 500, 25), str(recipe.get("english_name", "")), 14, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	var stamp := Panel.new()
	stamp.position = Vector2(949, 24)
	stamp.size = Vector2(68, 33)
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(0.42, 0.29, 0.15, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	stamp.add_theme_stylebox_override("panel", style)
	add_child(stamp)
	_label(stamp, Rect2(0, 1, 68, 28), str(recipe.get("type", recipe.get("category", "经典"))), 19, INK, HORIZONTAL_ALIGNMENT_CENTER)
	_label(self, Rect2(1035, 25, 142, 32), "已点亮" if recipe.get("unlocked", false) else "未点亮", 19, MUTED)
	var progress := MenuCatalog.ingredient_progress(recipe)
	_label(self, Rect2(1033, 62, 143, 25), "原料 %d / %d" % [progress.owned, progress.total], 16, MUTED)

func _left_column() -> void:
	_texture(self, Rect2(142, 115, 302, 277), CocktailDatabase.get_image(str(recipe.id)))
	if recipe.get("source_kind")=="diy" or recipe.get("unlock_kind")=="legendary_mastery":
		var preview:=preload("res://scripts/workbench_drink_preview.gd").new()
		preview.position=Vector2(142,115)
		preview.size=Vector2(302,277)
		preview.result=preload("res://scripts/research_data.gd").preview_result(recipe)
		preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
		add_child(preview)
	_label(self, Rect2(145, 397, 95, 32), "口感", 23)
	_label(self, Rect2(242, 401, 200, 30), " · ".join(recipe.get("mouthfeel_tags", recipe.get("tags", []))), 19, MUTED)
	_rule(self, Rect2(140, 430, 298, 5))
	var fields := ["alcohol_intensity", "sweetness", "sourness", "bitterness"]
	var names := ["酒感", "甜度", "酸度", "苦度"]
	for i in range(fields.size()):
		var y := 447 + i * 31
		_label(self, Rect2(146, y - 4, 63, 25), names[i], 19)
		var bar := Control.new()
		bar.set_script(SCORE)
		bar.position = Vector2(212, y + 6)
		bar.size = Vector2(174, 9)
		bar.set("value", float(recipe.get(fields[i], 0)))
		add_child(bar)
		_label(self, Rect2(398, y - 4, 38, 28), str(int(recipe.get(fields[i], 0))), 19, INK, HORIZONTAL_ALIGNMENT_RIGHT)
	_label(self, Rect2(145, 576, 292, 22), "统一感官试算 · 策划原值已保留" if recipe.has("design_attributes") else "试调记录 · 感官数值", 14, MUTED)
	_label(self, Rect2(145, 600, 250, 32), "风味标签", 23)
	_rule(self, Rect2(140, 634, 298, 5))
	var flavor_scroll := _scroll(self, Rect2(146, 644, 288, 45))
	flavor_scroll.name = "FlavorScroll"
	var flavors := HFlowContainer.new()
	flavors.name = "FlavorTags"
	flavors.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flavors.add_theme_constant_override("h_separation", 24)
	flavors.add_theme_constant_override("v_separation", 4)
	flavors.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flavor_scroll.add_child(flavors)
	for tag in recipe.get("flavor_tags", []):
		var text := Label.new()
		text.text = str(tag)
		text.add_theme_font_size_override("font_size", 20)
		text.add_theme_color_override("font_color", INK)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flavors.add_child(text)

static func amount_text(item: Dictionary) -> String:
	return preload("res://scripts/recipe_quantities.gd").amount_text(item)

func _ingredients_column() -> void:
	_label(self, Rect2(489, 115, 315, 35), "配方", 25)
	_rule(self, Rect2(482, 150, 343, 5))
	var scroll := _scroll(self, Rect2(487, 166, 339, 264))
	var list := VBoxContainer.new()
	list.name = "Ingredients"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	for ingredient: Dictionary in recipe.get("ingredients", []):
		var row := Control.new()
		row.custom_minimum_size = Vector2(327, 27)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_meta("sku_id", ingredient.get("sku_id", ""))
		list.add_child(row)
		var available := MenuCatalog.ingredient_available(ingredient)
		var box := Panel.new()
		box.position = Vector2(1, 5)
		box.size = Vector2(15, 15)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.4, 0.28, 0.1, 0.2) if available else Color.TRANSPARENT
		style.border_color = Color(0.37, 0.25, 0.12, 0.68)
		style.set_border_width_all(1)
		box.add_theme_stylebox_override("panel", style)
		row.add_child(box)
		var name_value := str(ingredient.name)
		var text := _label(row, Rect2(24, 0, 170, 26), name_value, 16 if name_value.length() > 8 else 18)
		text.clip_text = true
		row.tooltip_text = name_value + " " + amount_text(ingredient)
		_label(row, Rect2(197, 0, 73, 26), amount_text(ingredient), 16, MUTED)
		var remaining := float(MenuCatalog.inventory.get(ingredient.get("sku_id", ""), 0))
		var state_text := "已有"
		if not available:
			if remaining > 0:
				state_text = "余量不足"
			else:
				var supplies := get_node_or_null("/root/Supplies")
				var discovered := supplies != null and bool(supplies.call("is_unlocked", str(ingredient.get("sku_id", ""))))
				state_text = "已用完" if discovered else "缺少材料"
		var state_label := _label(row, Rect2(273, 0, 53, 26), state_text, 12 if state_text.length() > 3 else 15, MUTED)
		state_label.name = "IngredientStatus"
		row.tooltip_text += "\n当前库存：" + amount_text({"amount": remaining, "unit": ingredient.get("inventory_unit", ingredient.get("unit", "")), "name": name_value})
		if not ingredient.get("required", true):
			row.tooltip_text += "（可选，不影响点亮）"
			text.text += "＊"
	var ice_info: Array[String] = []
	for item: Dictionary in recipe.get("ice", []):
		ice_info.append(preload("res://scripts/recipe_quantities.gd").ice_text(item))
	if not ice_info.is_empty():
		var info := _label(self, Rect2(491, 435, 332, 25), "用冰  " + " · ".join(ice_info), 17, MUTED)
		info.name = "IceInfo"
		info.clip_text = true
		info.tooltip_text = "用冰  " + " · ".join(ice_info)
	_label(self, Rect2(489, 460, 315, 32), "所需器具", 23)
	_rule(self, Rect2(482, 492, 343, 5))
	var tools: Array = recipe.get("display_equipment", recipe.get("equipment", [])).duplicate()
	var glass := str(recipe.get("glass", ""))
	if not glass.is_empty():
		tools.append(glass)
	var width := 343.0 / maxi(tools.size(), 1)
	for i in range(tools.size()):
		var name_value := str(tools[i])
		var id := str(TOOL_ICONS.get(name_value, "mixing_glass"))
		var file := "res://assets/codex/tools/%s.svg" % id
		if ResourceLoader.exists(file):
			_texture(self, Rect2(484 + i * width, 500, width - 3, 67), load(file))
		var title := _label(self, Rect2(484 + i * width, 570, width - 3, 40), name_value.trim_prefix("冷却"), 15, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(self, Rect2(489, 611, 315, 32), "制作过程", 23)
	_rule(self, Rect2(482, 643, 343, 5))
	var method_scroll := _scroll(self, Rect2(491, 653, 330, 36))
	method_scroll.name = "MethodScroll"
	var methods := VBoxContainer.new()
	methods.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	method_scroll.add_child(methods)
	_flow_label(methods, str(recipe.get("preparation", "")), 17, MUTED)

func _scroll(parent: Node, rect: Rect2) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.position = rect.position
	scroll.size = rect.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(scroll)
	var scrollbar := scroll.get_v_scroll_bar()
	scrollbar.custom_minimum_size.x = 5
	for state in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.41, 0.28, 0.14, 0.08 if state == "scroll" else 0.35)
		style.set_corner_radius_all(0)
		scrollbar.add_theme_stylebox_override(state, style)
	return scroll

func _flow_label(parent: Node, value: String, font_size: int, color := INK) -> Label:
	var text := Label.new()
	text.text = value
	text.add_theme_font_size_override("font_size", font_size)
	if font_size >= 22:
		text.add_theme_font_override("font", get_theme_font("font", "Button"))
	text.add_theme_color_override("font_color", color)
	text.add_theme_constant_override("line_spacing", 5)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(text)
	return text

func _story_column() -> void:
	_label(self, Rect2(869, 115, 311, 35), "制作步骤", 25)
	_rule(self, Rect2(863, 150, 316, 5))
	var scroll := _scroll(self, Rect2(871, 164, 310, 336))
	scroll.name = "StepsScroll"
	var content := VBoxContainer.new()
	content.name = "Steps"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	var steps: Array = recipe.get("display_steps", recipe.get("steps", [])).duplicate(true)
	steps.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("number", 0)) < int(b.get("number", 0)))
	for i in range(steps.size()):
		var step: Dictionary = steps[i]
		var row := VBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 3)
		content.add_child(row)
		_flow_label(row, "%02d  %s" % [i + 1, step.get("operation", "")], 21)
		var description := _flow_label(row, str(step.get("instruction", "")), 17, MUTED)
		description.name = "StepDescription%d" % (i + 1)
	_rule(self, Rect2(863, 514, 316, 5))
	_label(self, Rect2(869, 529, 311, 35), "这杯酒的故事", 24)
	var story_scroll := _scroll(self, Rect2(871, 579, 310, 105))
	story_scroll.name = "StoryScroll"
	var stories := VBoxContainer.new()
	stories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_scroll.add_child(stories)
	var story := _flow_label(stories, str(recipe.get("story", "")), 18, MUTED)
	story.name = "CocktailStory"
