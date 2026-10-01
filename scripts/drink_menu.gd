extends Control
signal close_requested

const POSTER := preload("res://scripts/menu_poster.gd")
const DRINK_ICON := preload("res://scripts/menu_drink_icon.gd")
const PAPER := preload("res://assets/codex/journal-paper-v1.png")
const INK := Color("57391f")
const MUTED := Color("79562f")
const CREAM := Color("eed9b3")

var sample_mode := false
var step := 0
var selected: Array = []
var design: Dictionary = {}
var recipes: Array = []
var category := "全部"
var query := ""
var body: Control
var grid: GridContainer
var receipt: Control
var status: Label
var next_button: Button
var poster: Control
var drawing: Control
var brush_color := Color("56361f")
var brush_size := 4.0
var using_eraser := false
var undo_button: Button
var redo_button: Button
var prompt_edit: TextEdit
var export_dialog: FileDialog
var exporting := false
var active_request := -1
var revision := 0
var request_revision := -1
var brush_button: Button
var eraser_button: Button
var color_buttons: Array[Button] = []
var width_buttons: Array[Button] = []

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	selected = MenuCatalog.entries.duplicate(true)
	design = MenuCatalog.design.duplicate(true)
	_load_idea()
	recipes = MenuCatalog.unlocked_recipes()
	MenuArt.generation_finished.connect(_art_received)
	MenuArt.generation_failed.connect(_art_failed)
	MenuArt.availability_changed.connect(_provider_changed)
	_build()
	if not MenuCatalog.last_error.is_empty():
		_message(MenuCatalog.last_error)

func _exit_tree() -> void:
	if active_request >= 0:
		MenuArt.cancel()

func _style(fill: Color, border := Color.TRANSPARENT, width := 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(10)
	return box

func _panel(parent: Node, rect: Rect2, fill: Color, border := Color.TRANSPARENT) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _style(fill, border))
	parent.add_child(p)
	return p

func _label(parent: Node, rect: Rect2, value: String, font_size := 20, color := CREAM) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label

func _button(parent: Node, rect: Rect2, value: String, action: Callable, primary := false, on_paper := false) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = value
	button.focus_mode = FOCUS_NONE
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 20)
	var ink := INK if on_paper else CREAM
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", Color("fff0d0") if primary else ink)
	button.add_theme_color_override("font_pressed_color", ink)
	button.add_theme_color_override("font_disabled_color", Color(ink, 0.35))
	button.add_theme_stylebox_override("normal", _style(Color("96572f") if primary else Color(0.4, 0.25, 0.12, 0.03), Color("bd9459") if primary else Color(0.57, 0.39, 0.22, 0.4)))
	button.add_theme_stylebox_override("hover", _style(Color("a76b3a") if primary else Color(0.64, 0.42, 0.19, 0.18), Color("d3a45e")))
	button.add_theme_stylebox_override("pressed", _style(Color("7f4d2c") if primary else Color(0.53, 0.35, 0.16, 0.25), Color("d3a45e")))
	button.add_theme_stylebox_override("disabled", _style(Color(0.3, 0.22, 0.14, 0.12), Color(0.57, 0.39, 0.22, 0.16)))
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _paper(parent: Node, rect: Rect2) -> Control:
	var p := Control.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var texture := TextureRect.new()
	texture.texture = PAPER
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.size = rect.size
	texture.mouse_filter = MOUSE_FILTER_IGNORE
	p.add_child(texture)
	return p

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _build() -> void:
	if is_instance_valid(drawing):
		design.strokes = drawing.get_strokes()
	if is_instance_valid(body):
		remove_child(body)
		body.queue_free()
	poster = null
	drawing = null
	body = Control.new()
	body.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(body)
	_panel(body, Rect2(250, 122, 1324, 734), Color("2c2018"), Color("aa7d46"))
	_panel(body, Rect2(260, 132, 1304, 714), Color(0.14, 0.095, 0.065, 0.92), Color("65452c"))
	_label(body, Rect2(288, 146, 750, 50), "今晚，上哪几杯？" if step == 0 else "为今晚写一张酒单", 34)
	_label(body, Rect2(291, 198, 800, 27), "把拿手的几杯，留给远道而来的客人。" if step == 0 else "选一张旧纸，添几笔心意。", 17, Color("b59871"))
	_label(body, Rect2(1138, 151, 370, 33), "① 选酒    ───    ② 制作酒单", 19, Color("d3b47c"))
	if sample_mode:
		_label(body, Rect2(1192, 188, 300, 27), "样张预览 · 不计入正式上架", 15, Color("c99e62"))
	status = _label(body, Rect2(290, 809, 747, 28), "", 16, Color("cbb58f"))
	if step == 0:
		_build_selection()
	else:
		_build_editor()

func _build_selection() -> void:
	var paper := _paper(body, Rect2(283, 237, 794, 549))
	_label(paper, Rect2(35, 21, 365, 40), "从已点亮的酒谱中挑选" if not sample_mode else "先挑几杯，试试排版", 24, INK)
	var search := LineEdit.new()
	search.position = Vector2(443, 25)
	search.size = Vector2(314, 42)
	search.placeholder_text = "寻找酒名或风味"
	search.text = query
	search.add_theme_font_size_override("font_size", 18)
	search.add_theme_color_override("font_color", INK)
	search.add_theme_color_override("font_placeholder_color", MUTED)
	search.add_theme_stylebox_override("normal", _style(Color(0.95, 0.86, 0.68, 0.12), Color(0.5, 0.32, 0.14, 0.35)))
	search.add_theme_stylebox_override("focus", _style(Color(0.97, 0.9, 0.74, 0.4), Color("8d642f")))
	search.text_changed.connect(func(value: String): query = value; _refresh_cards())
	paper.add_child(search)
	var categories: Array = ["全部"]
	for recipe in recipes:
		if not categories.has(recipe.category):
			categories.append(recipe.category)
	var picker := OptionButton.new()
	picker.position = Vector2(37, 75)
	picker.size = Vector2(210, 38)
	picker.add_theme_color_override("font_color", INK)
	picker.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	picker.add_theme_font_size_override("font_size", 18)
	for value in categories:
		picker.add_item(str(value))
	picker.select(maxi(categories.find(category), 0))
	picker.item_selected.connect(func(index: int): category = str(categories[index]); _refresh_cards())
	paper.add_child(picker)
	_label(paper, Rect2(441, 78, 314, 27), "轻点酒卡加入，右侧可改售价", 16, MUTED)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(29, 122)
	scroll.size = Vector2(737, 393)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	paper.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	receipt = _paper(body, Rect2(1096, 237, 443, 549))
	_refresh_cards()
	_refresh_receipt()
	next_button = _button(body, Rect2(1230, 800, 308, 43), "选好了，制作酒单  →", _go_editor, true)
	next_button.name = "MakeMenu"
	next_button.disabled = selected.is_empty()
	if sample_mode:
		_button(body, Rect2(1047, 800, 167, 43), "回到正式酒单", _leave_samples)
	_message("最多选 6 款，可在右侧调整每杯售价。" if not recipes.is_empty() else "还没有点亮的酒谱，可以先看看酒单样张。")

func _refresh_cards() -> void:
	_clear(grid)
	var count := 0
	for recipe in recipes:
		if category != "全部" and str(recipe.category) != category:
			continue
		var haystack: String = str(recipe.name) + str(recipe.get("english_name", "")) + " ".join(recipe.tags)
		if not query.strip_edges().is_empty() and not haystack.to_lower().contains(query.strip_edges().to_lower()):
			continue
		var chosen := _selected_index(str(recipe.id)) >= 0
		var card := _button(grid, Rect2(0, 0, 234, 184), "", _toggle_recipe.bind(str(recipe.id)), false, true)
		card.custom_minimum_size = Vector2(234, 184)
		card.name = "Recipe_" + str(recipe.id)
		card.add_theme_stylebox_override("normal", _style(Color(0.47, 0.3, 0.11, 0.1 if chosen else 0.015), Color(0.48, 0.3, 0.13, 0.65 if chosen else 0.15)))
		_add_drink_art(card, Rect2(14, 14, 71, 75), recipe)
		_label(card, Rect2(99, 22, 119, 32), "已选  ✓" if chosen else str(recipe.category), 17, INK if chosen else MUTED)
		var price_hint := "售价由你定" if recipe.get("price_status", "") == "editor_starting_value" else "参考 %d 金币" % int(recipe.reference_price)
		_label(card, Rect2(99, 57, 124, 26), price_hint, 15, MUTED)
		_label(card, Rect2(17, 102, 203, 36), str(recipe.name), 23, INK)
		_label(card, Rect2(17, 143, 204, 25), " · ".join(recipe.tags), 15, MUTED)
		count += 1
	if count == 0:
		var empty := Control.new()
		empty.custom_minimum_size = Vector2(736, 382)
		grid.add_child(empty)
		_label(empty, Rect2(182, 93, 442, 47), "酒谱还空着" if recipes.is_empty() else "没有找到这杯酒", 30, INK)
		_label(empty, Rect2(183, 153, 511, 57), "点亮酒谱后，就能把它写进今晚的酒单。" if recipes.is_empty() else "换个酒名或风味找找看。", 19, MUTED)
		if recipes.is_empty():
			var button := _button(empty, Rect2(183, 236, 285, 49), "查看样张，先试一试  →", _enter_samples, false, true)
			button.name = "PreviewSamples"

func _add_drink_art(parent: Node, rect: Rect2, recipe: Dictionary) -> void:
	var path: String = recipe.get("thumbnail", "")
	if not path.is_empty() and ResourceLoader.exists(path):
		var art := TextureRect.new()
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.texture = load(path)
		art.position = rect.position
		art.size = rect.size
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = MOUSE_FILTER_IGNORE
		parent.add_child(art)
		return
	var icon := Control.new()
	icon.set_script(DRINK_ICON)
	icon.position = rect.position
	icon.size = rect.size
	var id := str(recipe.id)
	icon.kind = "highball" if id.contains("mojito") or id.contains("tonic") else ("coupe" if id.contains("margarita") or id.contains("sour") else "rocks")
	icon.tint = Color("b5b76f") if icon.kind == "highball" else Color("d8aa62") if icon.kind == "coupe" else Color("bf7a37")
	parent.add_child(icon)

func _refresh_receipt() -> void:
	# Keep the paper texture, replace only its ink and editable rows.
	for child in receipt.get_children():
		if not child is TextureRect:
			receipt.remove_child(child)
			child.queue_free()
	_label(receipt, Rect2(34, 26, 336, 40), "今晚的选择", 27, INK)
	_label(receipt, Rect2(34, 76, 368, 29), "已选 %d / 6 款      售价 / 金币" % selected.size(), 17, MUTED)
	if selected.is_empty():
		_label(receipt, Rect2(42, 204, 340, 85), "先挑一杯拿手的。\n客人会记得这个味道。", 23, MUTED)
	for i in range(selected.size()):
		var entry: Dictionary = selected[i]
		var recipe := _recipe(str(entry.id))
		var y := 118 + i * 57
		_label(receipt, Rect2(35, y + 6, 210, 35), str(recipe.get("name", "")), 21, INK)
		var price := SpinBox.new()
		price.position = Vector2(247, y + 3)
		price.size = Vector2(105, 42)
		price.min_value = 1
		price.max_value = 9999
		price.step = 1
		price.value = entry.price
		price.add_theme_font_size_override("font_size", 20)
		price.get_line_edit().add_theme_color_override("font_color", INK)
		price.get_line_edit().add_theme_stylebox_override("normal", _style(Color(1, 0.92, 0.75, 0.22), Color(0.5, 0.35, 0.16, 0.2)))
		price.value_changed.connect(func(value: float):
			entry.price = value
			revision += 1
		)
		receipt.add_child(price)
		_button(receipt, Rect2(364, y + 3, 40, 42), "×", _toggle_recipe.bind(str(entry.id)), false, true)
	_label(receipt, Rect2(35, 481, 370, 41), "好酒不必太多，合心意就好。", 17, MUTED)
	if is_instance_valid(next_button):
		next_button.disabled = selected.is_empty()

func _selected_index(id: String) -> int:
	for i in range(selected.size()):
		if selected[i].id == id:
			return i
	return -1

func _recipe(id: String) -> Dictionary:
	for recipe in recipes:
		if recipe.id == id:
			return recipe
	return {}

func _toggle_recipe(id: String) -> void:
	var index := _selected_index(id)
	if index >= 0:
		selected.remove_at(index)
	elif selected.size() >= 6:
		_message("这张纸最多写六杯，先撤下一杯再试试。")
		return
	else:
		var recipe := _recipe(id)
		selected.append({"id": id, "price": recipe.reference_price})
	revision += 1
	_refresh_cards()
	_refresh_receipt()

func _enter_samples() -> void:
	sample_mode = true
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/menu_samples.json"))
	recipes = data.recipes
	selected = []
	for recipe in recipes.slice(0, 4):
		selected.append({"id": recipe.id, "price": recipe.reference_price})
	design = MenuCatalog.DEFAULT_DESIGN.duplicate(true)
	var path := MenuCatalog.save_path + ".sample"
	if FileAccess.file_exists(path):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if saved is Dictionary and saved.get("entries") is Array and MenuCatalog._valid_design(saved.get("design")):
			var candidate: Array = []
			var seen: Array = []
			for entry in saved.entries:
				if entry is Dictionary and entry.get("id") is String and not _recipe(entry.id).is_empty() and not seen.has(entry.id) and MenuCatalog._number(entry.get("price"), 1, 9999):
					candidate.append(entry)
					seen.append(entry.id)
			if candidate.size() <= 6:
				selected = candidate
				design = saved.design
	query = ""
	category = "全部"
	_load_idea()
	_build()

func _load_idea() -> void:
	var path := MenuCatalog.save_path + ".idea.txt"
	if not FileAccess.file_exists(path):
		return
	var idea: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if idea is Dictionary and idea.get("style_prompt") is String:
		design.ai_prompt = idea.style_prompt.left(600)

func _leave_samples() -> void:
	sample_mode = false
	step = 0
	drawing = null
	selected = MenuCatalog.entries.duplicate(true)
	design = MenuCatalog.design.duplicate(true)
	recipes = MenuCatalog.unlocked_recipes()
	query = ""
	category = "全部"
	_build()

func _go_editor() -> void:
	if selected.is_empty():
		return
	step = 1
	_build()

func _go_selection() -> void:
	step = 0
	_build()

func _selected_drinks() -> Array:
	var result: Array = []
	for entry in selected:
		var recipe := _recipe(str(entry.id)).duplicate(true)
		if recipe.is_empty():
			continue
		recipe.price = entry.price
		result.append(recipe)
	return result

func _build_editor() -> void:
	_panel(body, Rect2(283, 237, 438, 549), Color("47311f"), Color("8a653e"))
	poster = Control.new()
	poster.set_script(POSTER)
	poster.name = "MenuPoster"
	poster.position = Vector2(319, 238)
	poster.size = Vector2(366, 549)
	poster.drinks = _selected_drinks()
	poster.design = design.duplicate(true)
	poster.sample = sample_mode
	body.add_child(poster)
	drawing = poster.drawing
	drawing.editable = design.method == "draw"
	drawing.ink_color = brush_color
	drawing.brush_width = brush_size
	drawing.eraser = using_eraser
	drawing.strokes_changed.connect(_ink_changed)
	var methods := ["template", "draw", "ai"]
	var titles := ["Ⅰ  酒馆模板", "Ⅱ  自己画", "Ⅲ  AI 画师"]
	var notes := ["旧纸新墨，挑一款就好", "亲手添上酒馆的印记", "让一个想法长出模样"]
	for i in range(3):
		var b := _button(body, Rect2(751 + i * 267, 239, 251, 85), "", _set_method.bind(methods[i]))
		b.name = "Method_" + methods[i]
		if design.method == methods[i]:
			b.add_theme_stylebox_override("normal", _style(Color("563b25"), Color("d6ac6c"), 2))
		_label(b, Rect2(17, 10, 224, 32), titles[i], 23)
		_label(b, Rect2(17, 48, 226, 25), notes[i], 15, Color("bb9c73"))
	_label(body, Rect2(756, 345, 352, 28), "酒单题字", 18, Color("bca079"))
	_text_field(Rect2(754, 382, 352, 46), str(design.title), 18, func(value: String):
		design.title = value if not value.strip_edges().is_empty() else "今晚的酒单"
		_refresh_poster()
	)
	_label(body, Rect2(1130, 345, 383, 28), "落款", 18, Color("bca079"))
	_text_field(Rect2(1128, 382, 408, 46), str(design.subtitle), 28, func(value: String): design.subtitle = value; _refresh_poster())
	match str(design.method):
		"template": _build_templates()
		"draw": _build_drawing_tools()
		"ai": _build_ai_tools()
	_button(body, Rect2(752, 800, 191, 43), "←  再挑几杯", _go_selection)
	_button(body, Rect2(963, 800, 189, 43), "导出图片", _show_export)
	var save := _button(body, Rect2(1172, 800, 364, 43), "保存样张" if sample_mode else "挂上今晚的酒单", _save, true)
	save.name = "SaveMenu"
	if design.method == "ai" and str(design.get("ai_image_path", "")).is_empty():
		save.text = "保存风格想法"
	_message("样张只供设计预览，不会加入正式上架酒单。" if sample_mode else "酒名与价格会自动排好，保存后用于今晚的酒单。")

func _text_field(rect: Rect2, value: String, limit: int, action: Callable) -> void:
	var field := LineEdit.new()
	field.position = rect.position
	field.size = rect.size
	field.text = value
	field.max_length = limit
	field.add_theme_font_size_override("font_size", 22)
	field.add_theme_color_override("font_color", CREAM)
	field.add_theme_stylebox_override("normal", _style(Color("39291d"), Color("84613d")))
	field.add_theme_stylebox_override("focus", _style(Color("483120"), Color("d1aa70")))
	field.text_changed.connect(action)
	body.add_child(field)

func _build_templates() -> void:
	_label(body, Rect2(756, 454, 530, 32), "挑一张与酒馆相衬的纸", 23)
	for i in range(2):
		var key := "parchment" if i == 0 else "nocturne"
		var tile := _button(body, Rect2(754 + i * 399, 502, 381, 150), "", _set_template.bind(key))
		tile.name = "Template_" + key
		var swatch := _panel(tile, Rect2(20, 20, 72, 105), Color("e7ca92") if i == 0 else Color("2e241e"), Color("b79a62"))
		_label(swatch, Rect2(9, 32, 57, 35), "酒单", 20, INK if i == 0 else CREAM)
		_label(tile, Rect2(115, 25, 250, 34), "荒野旧纸" if i == 0 else "午夜烫金", 25)
		_label(tile, Rect2(115, 72, 250, 26), "暖色纸纹 · 手写感" if i == 0 else "深棕底色 · 金色墨迹", 17, Color("b99a70"))
		if design.template == key:
			_label(tile, Rect2(285, 111, 77, 26), "已选 ✓", 16, Color("e9bf79"))
	_label(body, Rect2(758, 686, 742, 63), "名字与价格落在纸上，留白留给每一杯酒。\n换一张纸，已经写下的字和画也会保留。", 19, Color("ba9c76"))

func _build_drawing_tools() -> void:
	_label(body, Rect2(756, 454, 650, 33), "直接在左边的纸上落笔", 23)
	brush_button = _button(body, Rect2(754, 507, 123, 44), "画笔", func(): _set_eraser(false))
	eraser_button = _button(body, Rect2(888, 507, 139, 44), "整笔橡皮", func(): _set_eraser(true))
	(brush_button if not using_eraser else eraser_button).add_theme_stylebox_override("normal", _style(Color("694728"), Color("e1b375")))
	undo_button = _button(body, Rect2(1043, 507, 105, 44), "撤销", func(): drawing.undo())
	redo_button = _button(body, Rect2(1160, 507, 105, 44), "重做", func(): drawing.redo())
	_button(body, Rect2(1281, 507, 126, 44), "清空画稿", func(): drawing.clear_canvas())
	_label(body, Rect2(756, 575, 99, 34), "墨色", 20, Color("bfa17b"))
	var colors := ["56361f", "975332", "b28a3d", "626c45", "4c6570", "eee0ba"]
	color_buttons.clear()
	for i in range(colors.size()):
		var color := Color(colors[i])
		var b := _button(body, Rect2(839 + i * 60, 574, 45, 40), "✓" if brush_color.is_equal_approx(color) else "", _set_color.bind(color))
		b.add_theme_stylebox_override("normal", _style(color, Color("d1b887"), 2))
		b.add_theme_color_override("font_color", Color.WHITE if i < 5 else INK)
		b.set_meta("ink", color)
		color_buttons.append(b)
	_label(body, Rect2(756, 638, 99, 33), "笔触", 20, Color("bfa17b"))
	width_buttons.clear()
	for i in range(3):
		var width: float = [2.0, 4.0, 8.0][i]
		var b := _button(body, Rect2(838 + i * 121, 635, 108, 42), ["细", "中", "粗"][i], _set_brush.bind(width))
		if is_equal_approx(brush_size, width):
			b.add_theme_stylebox_override("normal", _style(Color("694728"), Color("e1b375")))
		b.set_meta("width", width)
		width_buttons.append(b)
	_label(body, Rect2(758, 703, 736, 55), "鼠标或手指都能画。橡皮擦去整条笔迹。\n酒名与价格会一直清楚地留在纸上。", 18, Color("ba9c76"))
	_update_history_buttons()

func _set_eraser(value: bool) -> void:
	using_eraser = value
	drawing.eraser = value
	for button in [brush_button, eraser_button]:
		button.add_theme_stylebox_override("normal", _style(Color(0.4, 0.25, 0.12, 0.03), Color(0.57, 0.39, 0.22, 0.4)))
	(eraser_button if value else brush_button).add_theme_stylebox_override("normal", _style(Color("694728"), Color("e1b375")))

func _set_color(value: Color) -> void:
	brush_color = value
	using_eraser = false
	# Keep the same canvas to retain its undo/redo history.
	drawing.ink_color = value
	_set_eraser(false)
	for button in color_buttons:
		button.text = "✓" if value.is_equal_approx(button.get_meta("ink")) else ""
	_message("换好了墨色，可以继续画。")

func _set_brush(value: float) -> void:
	brush_size = value
	drawing.brush_width = value
	for button in width_buttons:
		button.add_theme_stylebox_override("normal", _style(Color("694728"), Color("e1b375")) if is_equal_approx(value, button.get_meta("width")) else _style(Color(0.4, 0.25, 0.12, 0.03), Color(0.57, 0.39, 0.22, 0.4)))
	_message("已换成%s笔触。" % ("细" if value == 2 else "中" if value == 4 else "粗"))

func _ink_changed() -> void:
	if is_instance_valid(drawing):
		design.strokes = drawing.get_strokes()
	_update_history_buttons()
	revision += 1

func _update_history_buttons() -> void:
	if is_instance_valid(drawing) and is_instance_valid(undo_button) and is_instance_valid(redo_button):
		undo_button.disabled = not drawing.can_undo()
		redo_button.disabled = not drawing.can_redo()

func _build_ai_tools() -> void:
	_label(body, Rect2(756, 454, 748, 32), "想要一张什么样的酒单？", 23)
	prompt_edit = TextEdit.new()
	prompt_edit.position = Vector2(754, 506)
	prompt_edit.size = Vector2(782, 130)
	prompt_edit.placeholder_text = "例如：像一封从荒野寄来的旧信，边角画一点野花，暖色、安静，留出清楚的酒名和价格。"
	prompt_edit.text = str(design.get("ai_prompt", ""))
	prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	prompt_edit.add_theme_font_size_override("font_size", 20)
	prompt_edit.add_theme_color_override("font_color", CREAM)
	prompt_edit.add_theme_stylebox_override("normal", _style(Color("39291d"), Color("84613d")))
	prompt_edit.text_changed.connect(func(): design.ai_prompt = prompt_edit.text.left(600); revision += 1)
	body.add_child(prompt_edit)
	var generate := _button(body, Rect2(1230, 655, 305, 47), "正在作画…" if active_request >= 0 else "请画师画一张", _generate_art, true)
	generate.disabled = not MenuArt.is_available() or active_request >= 0
	_label(body, Rect2(758, 654, 450, 51), "会参考已选的 %d 款酒与风味。" % selected.size(), 18, Color("ba9c76"))
	_label(body, Rect2(758, 721, 771, 50), "AI 画师还没到，可以先记下想法。" if not MenuArt.is_available() else "画稿只负责装饰，酒名和价格由酒馆写上。", 18, Color("c7ad85"))

func _set_method(value: String) -> void:
	if active_request >= 0:
		MenuArt.cancel()
		active_request = -1
	design.method = value
	_build()

func _set_template(value: String) -> void:
	design.template = value
	_build()

func _refresh_poster() -> void:
	if not is_instance_valid(poster):
		return
	# Preserve the drawing node and its undo history when text changes.
	design.strokes = drawing.get_strokes()
	poster.design = design.duplicate(true)
	poster.rebuild()
	drawing = poster.drawing
	drawing.editable = design.method == "draw"
	drawing.ink_color = brush_color
	drawing.brush_width = brush_size
	drawing.eraser = using_eraser
	if not drawing.strokes_changed.is_connected(_ink_changed):
		drawing.strokes_changed.connect(_ink_changed)
	revision += 1
	_update_history_buttons()

func _generate_art() -> void:
	var payload := MenuArt.build_request(str(design.get("ai_prompt", "")), _selected_drinks(), str(design.title), str(design.subtitle))
	request_revision = revision
	active_request = MenuArt.generate(payload)
	_build()

func _art_received(id: int, path: String) -> void:
	if id != active_request:
		return
	active_request = -1
	if request_revision != revision:
		_build()
		_message("酒单已改过，请按新的选择再画一张。")
		return
	design.ai_image_path = path
	_build()
	_message("新画稿已经到了，满意后就保存吧。")

func _art_failed(id: int, message: String) -> void:
	if id == active_request:
		active_request = -1
		_build()
		_message(message)

func _provider_changed() -> void:
	if step == 1 and design.method == "ai":
		_build()

func _message(value: String) -> void:
	if is_instance_valid(status):
		status.text = value

func _save() -> void:
	design.strokes = drawing.get_strokes()
	if design.method == "ai" and str(design.get("ai_image_path", "")).is_empty():
		var ideas := FileAccess.open(MenuCatalog.save_path + ".idea.txt", FileAccess.WRITE)
		if ideas == null:
			_message("想法没能保存，请检查存储空间。")
			return
		ideas.store_string(JSON.stringify(MenuArt.build_request(str(design.get("ai_prompt", "")), _selected_drinks(), str(design.title), str(design.subtitle)), "\t"))
		ideas.close()
		_message("风格想法已记下。画师到来后，可以接着画。")
		return
	if sample_mode:
		var path := MenuCatalog.save_path + ".sample"
		var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
		if file == null:
			_message("样张没能保存，请检查存储空间。")
			return
		file.store_string(JSON.stringify({"entries": selected, "design": design}, "", true, true))
		file.flush()
		var error := file.get_error()
		file.close()
		if error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path)) != OK:
			_message("样张没能保存，请重试。")
			return
		_message("样张已保存，下次还可以接着画。")
	elif MenuCatalog.save_menu(selected, design):
		_message("今晚的酒单挂好了。")
	else:
		_message(MenuCatalog.last_error)

func _show_export() -> void:
	if exporting:
		return
	if not is_instance_valid(export_dialog):
		export_dialog = FileDialog.new()
		export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		export_dialog.access = FileDialog.ACCESS_FILESYSTEM
		export_dialog.filters = PackedStringArray(["*.png ; 酒单图片"])
		export_dialog.title = "保存酒单图片"
		export_dialog.use_native_dialog = true
		export_dialog.file_selected.connect(export_png)
		add_child(export_dialog)
	export_dialog.current_file = "酒单样张.png" if sample_mode else "今晚的酒单.png"
	export_dialog.popup_centered_ratio(0.65)

func export_png(path: String) -> bool:
	if exporting:
		return false
	exporting = true
	design.strokes = drawing.get_strokes()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1080, 1620)
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var print_copy := Control.new()
	print_copy.set_script(POSTER)
	print_copy.theme = theme
	print_copy.size = Vector2(1080, 1620)
	print_copy.drinks = _selected_drinks()
	print_copy.design = design.duplicate(true)
	print_copy.sample = sample_mode
	viewport.add_child(print_copy)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := viewport.get_texture().get_image().save_png(path)
	viewport.queue_free()
	exporting = false
	_message("酒单图片已保存。" if error == OK else "图片没能保存，请检查目标文件夹。")
	return error == OK

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if step == 1:
			_go_selection()
		else:
			close_requested.emit()
		get_viewport().set_input_as_handled()
