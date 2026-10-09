extends Control
## A reusable parchment journal: six independent data-driven card slots per page.
signal close_requested
signal page_turned(page: int)

const PAGE_COUNT := 3
const PAGE_SIZE := Vector2(1280, 704)
const PAGE_ORIGIN := Vector2(284, 136)
const INK := Color("493019")
const TURN_SECONDS := 0.82
const INK_BUTTON_SCRIPT := preload("res://scripts/journal_ink_button.gd")
const CARD_SCRIPT := preload("res://scripts/journal_card.gd")
const BINDING_SCRIPT := preload("res://scripts/journal_binding.gd")
const TURN_SHADER := preload("res://assets/codex/page_turn.gdshader")
const LOCKED_SHADER := preload("res://assets/codex/locked_drink.gdshader")
const DETAIL_SCRIPT := preload("res://scripts/cocktail_detail.gd")

var page_index := 0
var selected_filter := 0
var turning := false
var _catalog_refresh_pending := false
var page_content: Control
var previous_button: Button
var next_button: Button
var tabs: Array[Button] = []
var curl: TextureRect
var snapshot: SubViewport
var turn_tween: Tween
var paper: Texture2D
var press_position := Vector2.ZERO
var press_active := false
var reserved_tutorial_slot := true
var allow_locked_details := false
var detail_id := ""
var navigation_hint: Label
var research_button: Button

func _ready() -> void:
	_load_settings()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper = load("res://assets/codex/journal-paper-v1.png")
	_build_frame()
	page_content = _make_page(page_index)
	page_content.position = PAGE_ORIGIN
	add_child(page_content)
	# The turning leaf is captured in its own viewport; no screen readback is needed.
	snapshot = SubViewport.new()
	snapshot.size = Vector2i(PAGE_SIZE)
	snapshot.transparent_bg = true
	snapshot.gui_disable_input = true
	snapshot.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(snapshot)
	curl = TextureRect.new()
	curl.name = "TurningLeaf"
	curl.position = PAGE_ORIGIN
	curl.size = PAGE_SIZE
	curl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	curl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curl.texture = snapshot.get_texture()
	var material_instance := ShaderMaterial.new()
	material_instance.shader = TURN_SHADER
	material_instance.set_shader_parameter("paper_texture", paper)
	curl.material = material_instance
	curl.hide()
	add_child(curl)
	_build_controls()
	var binding := Control.new()
	binding.set_script(BINDING_SCRIPT)
	binding.position = Vector2(249, 136)
	binding.size = Vector2(80, 704)
	add_child(binding)
	_update_controls()
	MenuCatalog.changed.connect(_catalog_changed)
	WorkbenchSession.changed.connect(_catalog_changed)

func _recipe(id: String) -> Dictionary:
	var r:=MenuCatalog.get_recipe(id)
	if r.is_empty(): r=WorkbenchSession.research_state().recipes.get(id,{}).duplicate(true)
	return r

func _load_settings() -> void:
	var settings: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/codex_settings.json"))
	if settings is Dictionary:
		reserved_tutorial_slot = settings.get("reserved_tutorial_slot", true) == true
		allow_locked_details = settings.get("allow_locked_details", false) == true

func _catalog_changed() -> void:
	if turning:
		_catalog_refresh_pending = true
		return
	_catalog_refresh_pending = false
	if not detail_id.is_empty():
		var id := detail_id
		if _recipe(id).is_empty():
			close_detail()
		else:
			show_detail(id)
		return
	page_index = mini(page_index, _page_count() - 1)
	_replace_page(page_index)
	_update_controls()

func _visible_recipes() -> Array:
	if selected_filter==3: return WorkbenchSession.research_recipes()
	var records := MenuCatalog.all_recipes()
	records.append_array(WorkbenchSession.research_recipes())
	records.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("codex_order", 99999)) < int(b.get("codex_order", 99999)))
	if selected_filter == 0:
		return records
	return records.filter(func(recipe: Dictionary): return recipe.unlocked == (selected_filter == 1))

func _page_count() -> int:
	var count := _visible_recipes().size() + (1 if reserved_tutorial_slot and selected_filter!=3 else 0)
	# Keep the existing empty leaves and their turning animation for future recipes.
	return maxi(PAGE_COUNT, ceili(count / 6.0))

func _style(fill: Color, border: Color, thickness := 1) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(thickness)
	result.set_corner_radius_all(3)
	result.set_content_margin_all(4)
	return result

func _panel(parent: Node, rect: Rect2, style: StyleBoxFlat) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _label(parent: Node, rect: Rect2, text_value: String, font_size: int, color := INK, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	if font_size >= 22:
		label.add_theme_font_override("font", get_theme_font("font", "Button"))
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build_frame() -> void:
	var leather := _style(Color("372316"), Color("9b6b38"), 2)
	leather.shadow_color = Color(0, 0, 0, 0.5)
	leather.shadow_size = 12
	leather.shadow_offset = Vector2(0, 7)
	_panel(self, Rect2(242, 123, 1334, 732), leather)
	_panel(self, Rect2(252, 132, 1314, 711), _style(Color("52301b"), Color("aa7743")))
	for inset in [8, 5, 2]:
		_panel(self, Rect2(PAGE_ORIGIN + Vector2(inset, inset), PAGE_SIZE), _style(Color("bd955b"), Color("714c2a")))

func _make_page(index: int) -> Control:
	var sheet := Control.new()
	sheet.name = "JournalPage"
	sheet.size = PAGE_SIZE
	sheet.theme = theme
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := TextureRect.new()
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.texture = paper
	texture.size = PAGE_SIZE
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(texture)
	_label(sheet, Rect2(180, 15, 330, 61), "酒 馆 图 鉴", 38)
	_label(sheet, Rect2(510, 32, 504, 31), "S A L O O N  R E C I P E  J O U R N A L", 16)
	_label(sheet, Rect2(1030, 27, 166, 34), ("原创配方 %d 款" % WorkbenchSession.research_recipes().size()) if selected_filter==3 else "已点亮 %d / %d" % [MenuCatalog.unlocked_ids.size(), MenuCatalog.all_recipes().size()], 20)
	var records := _visible_recipes()
	var offset := 1 if reserved_tutorial_slot and selected_filter!=3 else 0
	for i in range(6):
		var card := Button.new()
		card.set_script(CARD_SCRIPT)
		card.name = "CardSlot%d" % (i + 1)
		card.position = Vector2(148 + (i % 3) * 328, 144 + floori(i / 3.0) * 246)
		card.size = Vector2(300, 230)
		card.clip_contents = true
		card.set_meta("slot_number", index * 6 + i + 1)
		var record_index := index * 6 + i - offset
		var occupied := record_index >= 0 and record_index < records.size()
		card.set("has_recipe", occupied)
		card.set_meta("has_recipe", occupied)
		card.disabled = not occupied
		card.focus_mode = Control.FOCUS_NONE if not occupied else Control.FOCUS_ALL
		sheet.add_child(card)
		if not occupied:
			_label(card, Rect2(22, 12, 80, 28), "%03d" % (index * 6 + i + 1), 16, Color("8b6a45"))
			continue
		var recipe: Dictionary = records[record_index]
		card.set_meta("cocktail_id", recipe.id)
		card.set("is_locked", not recipe.unlocked)
		card.disabled = not recipe.unlocked and not allow_locked_details
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not card.disabled else Control.CURSOR_ARROW
		card.pressed.connect(show_detail.bind(str(recipe.id)))
		card.tooltip_text = _missing_material_tooltip(str(recipe.id)) if not recipe.unlocked else "查看酒谱"
		_populate_card(card, recipe)
	_label(sheet, Rect2(170, 638, 550, 36), "好酒的故事，等你写下。", 18, Color("795731"))
	_label(sheet, Rect2(66, 230, 40, 290), "酒\n谱\n手\n记", 20, Color("947345"), HORIZONTAL_ALIGNMENT_CENTER)
	_label(sheet, Rect2(948, 638, 220, 36), "—  %02d / %02d  —" % [index + 1, _page_count()], 19, Color("795731"), HORIZONTAL_ALIGNMENT_CENTER)
	return sheet

func _missing_material_tooltip(recipe_id: String) -> String:
	var names: Array[String] = []
	var supplies := get_node_or_null("/root/Supplies")
	if supplies != null:
		var requirements: Dictionary = supplies.call("missing_recipe_requirements", recipe_id)
		for item: Dictionary in requirements.get("ingredients", []):
			var name_value := str(item.get("name", "")).strip_edges()
			if not name_value.is_empty() and not names.has(name_value):
				names.append(name_value)
	return "缺少：\n" + "\n".join(names)

func _populate_card(card: Button, recipe: Dictionary) -> void:
	var ink := INK if recipe.unlocked else Color("624e35")
	_label(card, Rect2(29, 13, 80, 28), "%03d" % int(recipe.get("codex_order", card.get_meta("slot_number"))), 15, Color("8b6a45"))
	var motif := str(recipe.get("decoration_id", "herbal"))
	if motif not in ["herbal", "mint_citrus", "citrus", "cherry"]:
		motif = "herbal"
	var art_path := "res://assets/codex/decorations/%s.svg" % motif
	if ResourceLoader.exists(art_path):
		var decoration := TextureRect.new()
		decoration.position = Vector2(15, 55)
		decoration.size = Vector2(90, 127)
		decoration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		decoration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		decoration.texture = load(art_path)
		decoration.modulate.a = 0.65
		decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(decoration)
	var drink := TextureRect.new()
	drink.name = "DrinkPicture"
	drink.position = Vector2(15, 36)
	drink.size = Vector2(144, 155)
	drink.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drink.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	drink.texture = CocktailDatabase.get_image(str(recipe.id))
	if drink.texture == null and not str(recipe.get("thumbnail", "")).is_empty() and ResourceLoader.exists(str(recipe.get("thumbnail", ""))):
		drink.texture = load(str(recipe.thumbnail))
	if not recipe.unlocked:
		var material_instance := ShaderMaterial.new()
		material_instance.shader = LOCKED_SHADER
		drink.material = material_instance
		drink.modulate.a = 0.82
	drink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(drink)
	if recipe.get("source_kind")=="diy":
		var preview:=preload("res://scripts/workbench_drink_preview.gd").new()
		preview.position=drink.position
		preview.size=drink.size
		preview.result=recipe.result
		preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
		card.add_child(preview)
	var stamp := _panel(card, Rect2(218, 14, 59, 29), _style(Color.TRANSPARENT, Color(0.40, 0.26, 0.11, 0.65)))
	_label(stamp, Rect2(0, 0, 59, 29), str(recipe.get("type", recipe.category)), 17, ink, HORIZONTAL_ALIGNMENT_CENTER)
	var title := _label(card, Rect2(153, 66, 133, 37), str(recipe.name), 24 if str(recipe.name).length() > 4 else 26, ink)
	title.clip_text = true
	var english := _label(card, Rect2(154, 106, 128, 41), str(recipe.get("english_name", "")), 12, Color("8b7354"))
	english.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(card, Rect2(153, 153, 132, 28), " · ".join(recipe.get("mouthfeel_tags", [])), 16, ink)
	_label(card, Rect2(43 if not recipe.unlocked else 25, 192, 127, 28), "已点亮" if recipe.unlocked else "未点亮", 16, ink)
	var progress := MenuCatalog.ingredient_progress(recipe)
	_label(card, Rect2(168, 193, 111, 27), "原料 %d / %d" % [progress.owned, progress.total], 15, ink, HORIZONTAL_ALIGNMENT_RIGHT)

func show_detail(id: String) -> void:
	if turning:
		return
	var recipe := _recipe(id)
	if recipe.is_empty() or (not recipe.unlocked and not allow_locked_details):
		return
	detail_id = id
	press_active = false
	var child_index := page_content.get_index()
	remove_child(page_content)
	page_content.queue_free()
	var detail := Control.new()
	detail.set_script(DETAIL_SCRIPT)
	detail.name = "CocktailDetail"
	detail.theme = theme
	detail.position = PAGE_ORIGIN
	detail.size = PAGE_SIZE
	detail.set("recipe", recipe)
	detail.set("paper", paper)
	detail.connect("back_requested", close_detail)
	page_content = detail
	add_child(detail)
	move_child(detail, child_index)
	_update_controls()

func close_detail() -> void:
	if detail_id.is_empty():
		return
	detail_id = ""
	_replace_page(page_index)
	_update_controls()

func _button(rect: Rect2, text_value: String) -> Button:
	var button := Button.new()
	button.set_script(INK_BUTTON_SCRIPT)
	button.position = rect.position
	button.size = rect.size
	button.text = text_value
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 23)
	# All surfaces are empty. Only text and a small pen underline respond to input.
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color("795b39"))
	button.add_theme_color_override("font_hover_color", Color("422915"))
	button.add_theme_color_override("font_pressed_color", Color("422915"))
	button.add_theme_color_override("font_focus_color", Color("422915"))
	button.add_theme_color_override("font_disabled_color", Color(0.40, 0.28, 0.17, 0.20))
	add_child(button)
	return button

func _build_controls() -> void:
	for i in range(4):
		var tab := _button(Rect2(PAGE_ORIGIN + Vector2(350 + i * 146, 88), Vector2(134, 44)), ["全部", "已点亮", "未点亮", "DIY"][i])
		tab.name = "Filter%d" % i
		tab.pressed.connect(_select_filter.bind(i))
		tabs.append(tab)
	previous_button = _button(Rect2(PAGE_ORIGIN + Vector2(18, 144), Vector2(116, 482)), "‹")
	previous_button.set("is_margin", true)
	previous_button.add_theme_font_size_override("font_size", 36)
	previous_button.name = "PreviousPage"
	previous_button.tooltip_text = "上一页 · ←"
	previous_button.pressed.connect(turn_page.bind(-1))
	next_button = _button(Rect2(PAGE_ORIGIN + Vector2(1120, 144), Vector2(144, 482)), "›")
	next_button.set("is_margin", true)
	next_button.add_theme_font_size_override("font_size", 36)
	next_button.name = "NextPage"
	next_button.tooltip_text = "下一页 · →"
	next_button.pressed.connect(turn_page.bind(1))
	navigation_hint = _label(self, Rect2(260, 860, 850, 28), "轻点卡片查看酒谱  ·  轻点纸张两侧，或左右滑动翻页", 15, Color("d2b789"))
	research_button=_button(Rect2(1245,853,280,42),"以此研发 →")
	for color_key in ["font_color","font_hover_color","font_pressed_color"]: research_button.add_theme_color_override(color_key,Color("efdab3"))
	research_button.pressed.connect(func():
		Navigation.research_view="entry"
		Navigation.research_base_id=detail_id
		Navigation.go_to(&"research")
	)

func _select_filter(index: int) -> void:
	if turning or not detail_id.is_empty():
		return
	selected_filter = index
	page_index = 0
	_replace_page(0)
	_update_controls()

func _update_controls() -> void:
	if is_instance_valid(research_button): research_button.visible=not detail_id.is_empty() and _recipe(detail_id).get("unlocked",false)
	var overview := detail_id.is_empty()
	if navigation_hint != null:
		navigation_hint.text = "轻点卡片查看酒谱  ·  轻点纸张两侧，或左右滑动翻页" if overview else "滚动查看完整步骤与故事  ·  点击「返回图鉴」返回"
	previous_button.visible = overview
	next_button.visible = overview
	previous_button.disabled = turning or page_index == 0
	next_button.disabled = turning or page_index == _page_count() - 1
	for i in range(tabs.size()):
		tabs[i].visible = overview
		tabs[i].disabled = turning
		tabs[i].set("ink_selected", i == selected_filter)
		tabs[i].add_theme_color_override("font_color", INK if i == selected_filter else Color("8b6a45"))
	if overview:
		for card in page_content.find_children("CardSlot*", "Button", false, false):
			if not card.get_meta("has_recipe", false):
				continue
			var recipe := _recipe(str(card.get_meta("cocktail_id", "")))
			card.disabled = recipe.is_empty() or (not recipe.get("unlocked", false) and not allow_locked_details)
			card.mouse_default_cursor_shape = Control.CURSOR_ARROW if card.disabled else Control.CURSOR_POINTING_HAND

func turn_page(direction: int) -> void:
	var target := page_index + direction
	if not detail_id.is_empty() or turning or direction not in [-1, 1] or target < 0 or target >= _page_count():
		return
	turning = true
	press_active = false
	_update_controls()
	# Next: lift the current leaf. Previous: lay the previous leaf back down.
	var captured := _make_page(page_index if direction > 0 else target)
	snapshot.add_child(captured)
	snapshot.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var start_progress := 0.0 if direction > 0 else 1.0
	var end_progress := 1.0 if direction > 0 else 0.0
	curl.material.set_shader_parameter("progress", start_progress)
	await get_tree().process_frame
	await get_tree().process_frame
	if direction > 0:
		_replace_page(target)
	curl.show()
	turn_tween = create_tween()
	turn_tween.tween_method(_set_curl_progress, start_progress, end_progress, TURN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await turn_tween.finished
	if direction < 0:
		_replace_page(target)
	curl.hide()
	snapshot.remove_child(captured)
	captured.queue_free()
	snapshot.render_target_update_mode = SubViewport.UPDATE_DISABLED
	page_index = target
	turning = false
	if _catalog_refresh_pending:
		_catalog_changed()
	else:
		_update_controls()
	page_turned.emit(page_index)

func _replace_page(index: int) -> void:
	var child_index := page_content.get_index()
	remove_child(page_content)
	page_content.queue_free()
	page_content = _make_page(index)
	page_content.position = PAGE_ORIGIN
	add_child(page_content)
	move_child(page_content, child_index)

func _set_curl_progress(value: float) -> void:
	curl.material.set_shader_parameter("progress", value)

func _input(event: InputEvent) -> void:
	if not detail_id.is_empty():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			close_detail()
			get_viewport().set_input_as_handled()
		return
	# Navigation remains usable during a turn; destroying the page cancels its tween.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_LEFT, KEY_RIGHT]:
			turn_page(-1 if event.keycode == KEY_LEFT else 1)
			get_viewport().set_input_as_handled()
	# Touch is also delivered here as an emulated mouse event by project settings.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed:
			press_active = not turning and Rect2(PAGE_ORIGIN + Vector2(100, 138), Vector2(1100, 490)).has_point(local)
			press_position = local
		elif press_active:
			press_active = false
			var delta: Vector2 = local - press_position
			if absf(delta.x) > 90 and absf(delta.x) > absf(delta.y) * 1.4:
				turn_page(1 if delta.x < 0 else -1)
				get_viewport().set_input_as_handled()
