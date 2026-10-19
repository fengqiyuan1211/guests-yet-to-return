extends Control
## A read-only view of the same stock used by the shop and workbench.
signal close_requested

const DESIGN_SIZE := Vector2(1600, 900)
const ITEMS_PER_PAGE := 6
const CATEGORIES := ["全部", "原酒", "配料", "装饰品", "器材", "杯型", "纪念品"]
const StoryItems := preload("res://scripts/story_items.gd")
const RecipePaper := preload("res://scripts/memory_recipe_paper.gd")
const ORNAMENT_PANEL := preload("res://scripts/ornament_panel.gd")
const INK := Color("493019")
const MUTED_INK := Color("896844")
const CREAM := Color("f1ddb5")
const GOLD := Color("c59a59")
const SECONDARY_TEXT := Color("bfa98a")

var selected_id := ""
var category := "全部"
var page_index := 0
var products: Array = []
var item_buttons: Array[Button] = []
var category_buttons: Array[Button] = []
var supplies: Node
var catalog: RefCounted
var canvas: Control
var backpack_panel: Panel
var backdrop: ColorRect
var item_grid: Control
var item_details: Panel
var previous_button: Button
var next_button: Button
var page_number: Label
var inventory_count: Label
var category_count: Label
var empty_state: Control
var empty_title: Label
var empty_note: Label
var detail_name: Label
var detail_english: Label
var detail_art: TextureRect
var detail_stock: Label
var detail_status: Label
var detail_note: Label
var paper_button: Button
var paper_view: Control
var detail_rows: Array[HBoxContainer] = []
var detail_values: Array[Label] = []
var _closing := false


class StorageGrid extends Control:
	func _draw() -> void:
		var inset := StyleBoxFlat.new()
		inset.bg_color = Color("2d261f")
		inset.border_color = Color("705438")
		inset.set_border_width_all(1)
		inset.border_width_top = 2
		inset.border_width_bottom = 2
		inset.set_corner_radius_all(0)
		for slot in range(6):
			draw_style_box(inset, Rect2((slot % 3) * 268, floori(slot / 3.0) * 238, 252, 221))


class ItemSlot extends Button:
	var art: TextureRect
	var hover_tween: Tween
	func _ready() -> void:
		mouse_entered.connect(_refresh_hover)
		mouse_exited.connect(_refresh_hover)
		focus_entered.connect(_refresh_hover)
		focus_exited.connect(_refresh_hover)
	func _refresh_hover() -> void:
		if art == null:
			return
		if hover_tween != null and hover_tween.is_valid():
			hover_tween.kill()
		hover_tween = create_tween()
		var highlighted := is_hovered() or has_focus()
		hover_tween.set_parallel(true)
		hover_tween.tween_property(art, "scale", Vector2.ONE * (1.025 if highlighted else 1.0), 0.15).set_trans(Tween.TRANS_SINE)
		hover_tween.tween_property(art, "modulate", Color(1.02, 1.02, 1.0) if highlighted else Color.WHITE, 0.15)
	func _draw() -> void:
		if button_pressed:
			for layer in range(3):
				var glow := PackedVector2Array()
				for i in range(32):
					var angle := TAU * i / 32.0
					glow.append(Vector2(size.x / 2 + cos(angle) * (61 + layer * 10), 89 + sin(angle) * (60 + layer * 9)))
				draw_colored_polygon(glow, Color(0.93, 0.77, 0.46, 0.017))
			for point in [Vector2(7, 7), Vector2(size.x - 7, 7), Vector2(7, size.y - 7), size - Vector2(7, 7)]:
				var x_direction := 1.0 if point.x < size.x / 2 else -1.0
				var y_direction := 1.0 if point.y < size.y / 2 else -1.0
				draw_line(point, point + Vector2(x_direction * 11, 0), Color("d9bb7e"), 2, true)
				draw_line(point, point + Vector2(0, y_direction * 11), Color("d9bb7e"), 2, true)
		var shadow := PackedVector2Array()
		for i in range(24):
			var angle := TAU * i / 24.0
			shadow.append(Vector2(size.x / 2 + cos(angle) * 44, 167 + sin(angle) * 4))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.30))


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	supplies = get_node_or_null("/root/Supplies")
	if supplies != null:
		catalog = supplies.get("catalog") as RefCounted
	_build()
	resized.connect(_fit_canvas)
	_fit_canvas()
	if supplies != null and supplies.has_signal("changed"):
		supplies.connect("changed", _refresh_inventory)
	WorkbenchSession.changed.connect(_refresh_inventory)
	_refresh_inventory()


func _style(fill: Color, border: Color, width := 1, radius := 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(4)
	return style


func _label(parent: Node, rect: Rect2, text_value: String, font_size := 20, color := INK, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text_value
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font_size >= 20:
		label.add_theme_font_override("font", get_theme_font("font", "Button"))
	parent.add_child(label)
	return label


func _button(parent: Node, rect: Rect2, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = label
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 20)
	parent.add_child(button)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBox
		style.set_content_margin_all(4)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	return button


func _image(parent: Node, rect: Rect2, texture: Texture2D) -> TextureRect:
	var image := TextureRect.new()
	image.position = rect.position
	image.size = rect.size
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image


func _line(parent: Node, rect: Rect2, color: Color) -> void:
	var line := ColorRect.new()
	line.position = rect.position
	line.size = rect.size
	line.color = color
	line.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(line)


func _build() -> void:
	backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.055, 0.039, 0.027, 0.58)
	backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	backdrop.mouse_filter = MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_backdrop_input)
	add_child(backdrop)
	canvas = Control.new()
	canvas.name = "Canvas"
	canvas.size = DESIGN_SIZE
	canvas.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(canvas)
	backpack_panel = ORNAMENT_PANEL.new()
	backpack_panel.name = "BackpackPanel"
	backpack_panel.position = Vector2(170, 76)
	backpack_panel.size = Vector2(1260, 748)
	backpack_panel.mouse_filter = MOUSE_FILTER_STOP
	var walnut := _style(Color("3a2c20"), Color("a17b48"), 3, 7)
	walnut.shadow_color = Color(0, 0, 0, 0.45)
	walnut.shadow_size = 16
	walnut.shadow_offset = Vector2(0, 8)
	backpack_panel.add_theme_stylebox_override("panel", walnut)
	canvas.add_child(backpack_panel)
	var icon := _image(backpack_panel, Rect2(43, 30, 38, 39), load("res://assets/icons/backpack.svg") as Texture2D)
	icon.name = "BackpackIcon"
	icon.modulate = Color("e1c38a")
	_label(backpack_panel, Rect2(96, 21, 310, 58), "物品栏", 35, CREAM)
	inventory_count = _label(backpack_panel, Rect2(916, 32, 211, 34), "", 20, SECONDARY_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	inventory_count.name = "InventoryCount"
	var close_button := _button(backpack_panel, Rect2(1168, 25, 49, 49), "×", _request_close)
	close_button.name = "CloseButton"
	close_button.tooltip_text = "收起背包"
	close_button.add_theme_font_size_override("font_size", 28)
	_style_inventory_button(close_button)
	_line(backpack_panel, Rect2(42, 93, 1175, 1), Color(0.65, 0.49, 0.30, 0.40))
	_build_categories()
	item_grid = StorageGrid.new()
	item_grid.name = "ItemGrid"
	item_grid.position = Vector2(42, 174)
	item_grid.size = Vector2(788, 459)
	item_grid.mouse_filter = MOUSE_FILTER_IGNORE
	backpack_panel.add_child(item_grid)
	_build_details()
	_build_empty_state()
	previous_button = _button(backpack_panel, Rect2(251, 665, 134, 46), "← 上一页", _turn_page.bind(-1))
	previous_button.name = "PreviousPage"
	_style_inventory_button(previous_button)
	page_number = _label(backpack_panel, Rect2(391, 665, 94, 46), "", 21, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	page_number.name = "PageNumber"
	next_button = _button(backpack_panel, Rect2(491, 665, 134, 46), "下一页 →", _turn_page.bind(1))
	next_button.name = "NextPage"
	_style_inventory_button(next_button)
	category_count = _label(backpack_panel, Rect2(858, 674, 359, 28), "", 18, SECONDARY_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	category_count.name = "CategoryCount"


func _build_categories() -> void:
	for i in range(CATEGORIES.size()):
		var button := _button(backpack_panel, Rect2(42 + i * 114, 112, 104, 43), CATEGORIES[i], _set_category.bind(CATEGORIES[i]))
		button.name = "Category_" + CATEGORIES[i]
		button.toggle_mode = true
		_style_inventory_button(button)
		category_buttons.append(button)
	_label(backpack_panel, Rect2(858, 113, 359, 41), "物品详情", 20, SECONDARY_TEXT, HORIZONTAL_ALIGNMENT_CENTER)


func _style_inventory_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _style(Color("30251c"), Color("735638")))
	button.add_theme_stylebox_override("hover", _style(Color("4a3827"), Color("ac8651")))
	button.add_theme_stylebox_override("pressed", _style(Color("c2a16a"), Color("e0c28a")))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color("d2ad70"), 2))
	button.add_theme_stylebox_override("disabled", _style(Color("34291f"), Color("514030")))
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", Color("fff0cc"))
	button.add_theme_color_override("font_pressed_color", Color("34251a"))
	button.add_theme_color_override("font_focus_color", CREAM)
	button.add_theme_color_override("font_disabled_color", Color("7c6850"))


func _build_details() -> void:
	item_details = Panel.new()
	item_details.name = "ItemDetails"
	item_details.position = Vector2(858, 174)
	item_details.size = Vector2(359, 491)
	item_details.mouse_filter = MOUSE_FILTER_IGNORE
	item_details.add_theme_stylebox_override("panel", _style(Color("2e251d"), Color("725538")))
	backpack_panel.add_child(item_details)
	detail_name = _label(item_details, Rect2(18, 17, 323, 37), "", 24, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	detail_name.name = "DetailName"
	detail_english = _label(item_details, Rect2(18, 57, 323, 26), "", 14, SECONDARY_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	detail_english.name = "DetailEnglish"
	detail_english.hide()
	detail_art = _image(item_details, Rect2(84, 65, 191, 192), null)
	detail_art.name = "DetailArt"
	detail_stock = _label(item_details, Rect2(18, 267, 323, 40), "", 27, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	detail_stock.name = "DetailQuantity"
	detail_status = _label(item_details, Rect2(18, 310, 323, 30), "", 17, SECONDARY_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	detail_status.name = "DetailUnit"
	_line(item_details, Rect2(25, 352, 309, 1), Color(0.67, 0.51, 0.32, 0.32))
	for i in range(3):
		var row := HBoxContainer.new()
		row.position = Vector2(25, 367 + i * 38)
		row.size = Vector2(309, 29)
		row.mouse_filter = MOUSE_FILTER_IGNORE
		item_details.add_child(row)
		var caption := Label.new()
		caption.custom_minimum_size.x = 135
		caption.mouse_filter = MOUSE_FILTER_IGNORE
		caption.add_theme_font_size_override("font_size", 18)
		caption.add_theme_color_override("font_color", SECONDARY_TEXT)
		row.add_child(caption)
		var value := Label.new()
		value.name = ["DetailCurrent", "DetailUnopened", "DetailTotal"][i]
		value.size_flags_horizontal = SIZE_EXPAND_FILL
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.mouse_filter = MOUSE_FILTER_IGNORE
		value.add_theme_font_size_override("font_size", 20)
		value.add_theme_color_override("font_color", CREAM)
		row.add_child(value)
		detail_rows.append(row)
		detail_values.append(value)
	detail_note = _label(item_details, Rect2(25, 372, 309, 83), "", 19, SECONDARY_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	detail_note.name = "DetailNote"
	paper_button = _button(item_details, Rect2(68, 415, 223, 48), "展开酒单", _open_paper)
	paper_button.hide()


func _build_empty_state() -> void:
	empty_state = Control.new()
	empty_state.name = "EmptyState"
	empty_state.position = Vector2(42, 174)
	empty_state.size = Vector2(1176, 459)
	empty_state.mouse_filter = MOUSE_FILTER_IGNORE
	backpack_panel.add_child(empty_state)
	var icon := _image(empty_state, Rect2(553, 124, 70, 72), load("res://assets/icons/backpack.svg") as Texture2D)
	icon.modulate = Color("978362")
	empty_title = _label(empty_state, Rect2(180, 218, 816, 46), "", 28, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	empty_title.name = "EmptyTitle"
	empty_note = _label(empty_state, Rect2(180, 272, 816, 74), "", 21, SECONDARY_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	empty_note.name = "EmptyNote"


func _fit_canvas() -> void:
	if canvas == null:
		return
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	canvas.scale = Vector2.ONE * factor
	canvas.position = (size - DESIGN_SIZE * factor) / 2


func _state(id: String) -> Dictionary:
	if not StoryItems.get_item(id).is_empty(): return StoryItems.get_state(id)
	return supplies.call("get_state", id) if supplies != null else {}


func _physically_owned(item: Dictionary) -> bool:
	var state := _state(str(item.id))
	if str(item.storage_mode) == "permanent":
		return bool(state.get("owned", false))
	return int(state.get("quantity", 0)) > 0


func _refresh_inventory() -> void:
	products.clear()
	var owned_count := 0
	if catalog != null:
		for item: Dictionary in catalog.call("list_items"):
			if not _physically_owned(item):
				continue
			owned_count += 1
			if category == "全部" or str(item.category) == category:
				products.append(item)
	for item: Dictionary in StoryItems.owned_items():
		owned_count += 1
		if category == "全部" or str(item.category) == category: products.append(item)
	page_index = clampi(page_index, 0, _page_count() - 1)
	var selected_index := _index_of_id(selected_id)
	if selected_index >= 0:
		# Removing an earlier stock entry should keep this selection in view.
		page_index = floori(selected_index / float(ITEMS_PER_PAGE))
	else:
		selected_id = str(products[page_index * ITEMS_PER_PAGE].id) if not products.is_empty() else ""
	inventory_count.text = "现有 %d 种物品" % owned_count
	for i in range(category_buttons.size()):
		category_buttons[i].set_pressed_no_signal(CATEGORIES[i] == category)
	_render_inventory()


func _index_of_id(id: String) -> int:
	for i in range(products.size()):
		if str(products[i].id) == id:
			return i
	return -1


func _page_count() -> int:
	return maxi(1, ceili(products.size() / float(ITEMS_PER_PAGE)))


func _set_category(value: String) -> void:
	if category == value:
		# A toggle click must keep the active tab selected.
		for button in category_buttons:
			button.set_pressed_no_signal(button.name == "Category_" + category)
		return
	category = value
	page_index = 0
	selected_id = ""
	_refresh_inventory()


func _turn_page(direction: int) -> void:
	var next_page := clampi(page_index + direction, 0, _page_count() - 1)
	if next_page == page_index:
		return
	page_index = next_page
	selected_id = str(products[page_index * ITEMS_PER_PAGE].id)
	_render_inventory()


func _render_inventory() -> void:
	for child in item_grid.get_children():
		item_grid.remove_child(child)
		child.queue_free()
	item_buttons.clear()
	var is_empty := products.is_empty()
	item_grid.visible = not is_empty
	item_details.visible = not is_empty
	empty_state.visible = is_empty
	if is_empty:
		empty_title.text = "背包还是空的" if category == "全部" else "暂时没有" + category
		empty_note.text = "去港口货栈备些货吧。\n买入的物品会收在这里。" if category in ["全部", "原酒", "配料", "装饰品"] else "拥有的%s会收在这里。" % category
		if supplies == null or catalog == null:
			empty_title.text = "背包暂时无法读取"
			empty_note.text = "稍后再打开看看。"
	else:
		for slot in range(ITEMS_PER_PAGE):
			var index := page_index * ITEMS_PER_PAGE + slot
			if index >= products.size():
				break
			_build_item_slot(products[index], slot)
	_update_page_controls()
	_render_details()


func _build_item_slot(item: Dictionary, slot: int) -> void:
	var button := ItemSlot.new()
	button.name = "Product_" + str(item.id)
	button.set_meta("item_id", str(item.id))
	button.set_meta("audio_item",str(item.id))
	button.position = Vector2((slot % 3) * 268, floori(slot / 3.0) * 238)
	button.size = Vector2(252, 228)
	button.toggle_mode = true
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	button.tooltip_text = str(item.name)
	var recessed := _style(Color("2d261f"), Color("705438"))
	recessed.border_width_top = 2
	recessed.border_width_bottom = 2
	button.add_theme_stylebox_override("normal", recessed)
	button.add_theme_stylebox_override("hover", _style(Color("3b3025"), Color("a5814d")))
	button.add_theme_stylebox_override("pressed", _style(Color("443527"), Color("c4a061"), 1))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), Color("ceab6d"), 2))
	button.pressed.connect(_select_item.bind(str(item.id)))
	item_grid.add_child(button)
	var art_rect := _item_art_rect(item)
	button.art = _image(button, art_rect, _texture(str(item.id)))
	button.art.pivot_offset = Vector2(art_rect.size.x / 2, art_rect.size.y)
	var name_label := _label(button, Rect2(9, 167, 234, 29), str(item.name), 20, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	name_label.name = "ItemName"
	var stock := _label(button, Rect2(9, 198, 234, 25), _stock_summary(item), 17, Color("dcc6a4"), HORIZONTAL_ALIGNMENT_CENTER)
	stock.name = "ItemStock"
	button.set_pressed_no_signal(str(item.id) == selected_id)
	item_buttons.append(button)


func _item_art_rect(item: Dictionary) -> Rect2:
	var height := 158.0
	if str(item.category) == "装饰品":
		height = 118.0
	var heights := {"tool_shaker": 158.0, "tool_jigger": 140.0, "tool_strainer": 154.0,
		"tool_muddler": 163.0, "tool_bar_spoon": 163.0, "tool_mixing_glass": 150.0,
		"sku_mint_leaf": 120.0, "sku_white_cane_sugar": 140.0}
	height = float(heights.get(str(item.id), height))
	return Rect2(35, 166 - height, 182, height)


func _texture(id: String) -> Texture2D:
	if not StoryItems.get_item(id).is_empty(): return StoryItems.texture(id)
	return catalog.call("get_texture", id) as Texture2D if catalog != null else null


func _stock_summary(item: Dictionary) -> String:
	var state := _state(str(item.id))
	if str(item.storage_mode) == "permanent":
		return "已拥有"
	return "%d %s" % [int(state.get("quantity", 0)), _quantity_unit(item)]


func _quantity_unit(item: Dictionary) -> String:
	return str(item.get("quantity_unit", "件"))


func _measure_unit(item: Dictionary) -> String:
	return str(item.get("measurement_unit", ""))


func _amount(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, round(value)) else "%.1f" % value


func _select_item(id: String) -> void:
	if _index_of_id(id) < 0:
		return
	selected_id = id
	for button in item_buttons:
		button.set_pressed_no_signal(str(button.get_meta("item_id")) == id)
	_render_details()


func _update_page_controls() -> void:
	page_number.text = "%d / %d" % [page_index + 1, _page_count()]
	previous_button.disabled = page_index == 0
	next_button.disabled = page_index + 1 >= _page_count()
	category_count.text = "%s · %d 种" % ["所有物品" if category == "全部" else category, products.size()]


func _detail_row(index: int, caption: String, value: String) -> void:
	var label := detail_rows[index].get_child(0) as Label
	label.text = caption
	detail_values[index].text = value
	detail_rows[index].show()


func _render_details() -> void:
	for row in detail_rows:
		row.hide()
	detail_note.hide()
	paper_button.hide()
	var index := _index_of_id(selected_id)
	if index < 0:
		return
	var item: Dictionary = products[index]
	var state := _state(selected_id)
	detail_name.text = str(item.name)
	detail_english.text = str(item.get("english_name", ""))
	detail_art.texture = _texture(selected_id)
	detail_stock.text = _stock_summary(item)
	if item.get("kind") == "story_item":
		detail_stock.text = "1 张"
		detail_status.text = "纪念品 · 小线赠予"
		detail_note.text = str(item.description)
		detail_note.size.y = 35
		detail_note.show()
		paper_button.show()
		return
	detail_note.size.y = 83
	var unit := _quantity_unit(item)
	match str(item.storage_mode):
		"container":
			var measure := _measure_unit(item)
			detail_status.text = "%s · %s装" % [item.category, unit]
			_detail_row(0, "当前%s余量" % unit, "%s %s" % [_amount(float(state.get("current_remaining", 0))), measure])
			_detail_row(1, "未开封", "%d %s" % [maxi(0, int(state.get("quantity", 0)) - 1), unit])
			var total: float = float(supplies.call("total_remaining", selected_id))
			_detail_row(2, "合计剩余", "%s %s" % [_amount(total), measure])
		"quantity":
			detail_status.text = "%s · 按%s计数" % [item.category, unit]
			_detail_row(0, "当前数量", "%d %s" % [int(state.get("quantity", 0)), unit])
		"permanent":
			detail_status.text = "%s · 可重复使用" % item.category
			detail_note.text = "已经放在酒馆里，\n调酒时随手取用。"
			detail_note.show()


func _open_paper() -> void:
	if is_instance_valid(paper_view) or not StoryItems.get_state(selected_id).get("owned", false): return
	paper_view = RecipePaper.new()
	add_child(paper_view)

func _backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		backdrop.accept_event()
		_request_close()
	elif event is InputEventScreenTouch and event.pressed:
		backdrop.accept_event()
		_request_close()


func _request_close() -> void:
	if _closing:
		return
	_closing = true
	close_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(paper_view): return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_request_close()
