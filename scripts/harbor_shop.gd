extends Control
signal close_requested

const CATALOG := preload("res://scripts/supply_catalog.gd")
const HARBOR_DAY_NIGHT := preload("res://scripts/harbor_day_night.gd")
const BACKGROUND_PATH := "res://assets/art/shop/harbor-shop-day.png"
const MERCHANT_PATH := "res://assets/art/shop/harbor-merchant.png"
const MERCHANT_LINES := [
	"船刚靠岸，今天的货都在这儿了。",
	"你慢慢挑，缺什么就跟我说。",
	"海上风大，今天这船比平时晚了些。",
]
const DESIGN_SIZE := Vector2(1600, 900)
const CATEGORIES := ["原酒", "配料", "装饰品"]
const SHELF_ORIGIN := Vector2(727, 124)
const INK := Color("3b2415")
const CREAM := Color("f4dfb8")
const GOLD := Color("d5af6c")

var category := "原酒"
var page := 0
var packages := 1
var selected_id := ""
var products: Array = []
var catalog := CATALOG.new()
var supplies: Node
var wallet: Node
var clock: Node
var canvas: Control
var harbor_lighting: HARBOR_DAY_NIGHT
var merchant_portrait: TextureRect
var shelves: Control
var slot_buttons: Array[Button] = []
var category_buttons: Array[Button] = []
var balance_label: Label
var time_label: Label
var page_label: Label
var previous_button: Button
var next_button: Button
var receipt_name: Label
var receipt_capacity: Label
var receipt_stock: Label
var receipt_hint: Label
var receipt_total: Label
var receipt_icon: TextureRect
var quantity_label: Label
var quantity_controls: Control
var minus_button: Button
var plus_button: Button
var buy_button: Button
var merchant_line: Label
var merchant_line_index := 0
var toast: Label
var toast_remaining := 0.0
var page_turning := false
var shelf_tween: Tween
var balance_feedback_tween: Tween
var purchase_feedback_sequence := 0
var purchase_feedback_layers: Array[Control] = []


class PurchaseCoin extends Control:
	const TEXTURE := preload("res://assets/icons/coin.svg")
	func _draw() -> void:
		var center := size * 0.5
		# A worn brass fill keeps the existing fine coin engraving readable on paper.
		draw_circle(center + Vector2(0, 1.5), size.x * 0.36, Color(0.17, 0.10, 0.04, 0.35))
		draw_circle(center, size.x * 0.34, Color("80532b"))
		draw_texture_rect(TEXTURE, Rect2(Vector2.ZERO, size), false, Color(1.12, 1.06, 0.96))


class MerchantInteraction extends Button:
	var portrait_alpha: Image
	var visible_height := 623.0
	func _has_point(point: Vector2) -> bool:
		# Follow the painted silhouette, including the centered texture's side padding.
		if portrait_alpha == null or not Rect2(0, 0, size.x, minf(size.y, visible_height)).has_point(point):
			return false
		var image_size := Vector2(portrait_alpha.get_size())
		var factor := minf(size.x / image_size.x, size.y / image_size.y)
		var padding := (size - image_size * factor) / 2.0
		if not Rect2(padding, image_size * factor).has_point(point):
			return false
		var pixel := Vector2i((point - padding) / factor)
		return portrait_alpha.get_pixelv(pixel).a > 0.15


class PaperSurface extends Control:
	const PAPER := preload("res://assets/codex/journal-paper-v1.png")
	var dark := false
	var hanging := false
	var marked := false
	var underline := true
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var points := PackedVector2Array([Vector2(7, 1), Vector2(w - 8, 2), Vector2(w - 1, 8), Vector2(w - 3, h - 7), Vector2(w - 10, h - 1), Vector2(9, h - 2), Vector2(2, h - 10), Vector2(1, 8), Vector2(7, 1)])
		draw_colored_polygon(points, Color("302014") if dark else Color("ead1a5"))
		if not dark:
			draw_texture_rect_region(PAPER, Rect2(4, 4, w - 8, h - 8), Rect2(460, 260, w - 8, h - 8), Color(1, 0.97, 0.93))
		draw_polyline(points, Color("ae8250") if dark else Color("aa7943"), 2, true)
		draw_rect(Rect2(10, 10, w - 20, h - 20), Color("b48c59") if dark else Color("a67846"), false, 1)
		for i in range(18):
			var x := 12 + fposmod(i * 83.7, maxf(w - 25, 1))
			var y := 11 + fposmod(i * 37.2, maxf(h - 25, 1))
			draw_line(Vector2(x, y), Vector2(minf(x + 15, w - 10), y + 1), Color(0.42, 0.29, 0.15, 0.045), 1)
		for p in [Vector2(13, 13), Vector2(w - 13, 13), Vector2(13, h - 13), Vector2(w - 13, h - 13)]:
			draw_circle(p, 2.5, Color("b08751"))
			draw_arc(p, 4, 0, TAU, 12, Color("654321"), 1, true)
		if hanging:
			for x in [20.0, w - 20.0]:
				draw_line(Vector2(x, -18), Vector2(x, 10), Color("52361e"), 3, true)
				draw_arc(Vector2(x, 10), 4, 0, TAU, 12, Color("70502b"), 2, true)
		if marked:
			if underline:
				draw_line(Vector2(25, h - 12), Vector2(w - 25, h - 12), Color("6d4421"), 3, true)
			else:
				draw_rect(Rect2(7, 7, w - 14, h - 14), Color("6d4421"), false, 2)


class ShelfRack extends Control:
	func _draw() -> void:
		for x in [0.0, size.x - 23]:
			draw_rect(Rect2(x, 0, 23, size.y), Color("52351f"))
			draw_line(Vector2(x + 4, 0), Vector2(x + 4, size.y), Color("9b6c3a"), 2)
		for y in [256.0, 508.0]:
			draw_rect(Rect2(1, y + 17, size.x - 2, 37), Color(0.12, 0.07, 0.03, 0.5))
			draw_rect(Rect2(1, y, size.x - 2, 43), Color("764a29"))
			draw_rect(Rect2(1, y, size.x - 2, 8), Color("a77642"))
			draw_line(Vector2(0, y + 8), Vector2(size.x, y + 8), Color("d3a366"), 1)
			draw_line(Vector2(0, y + 41), Vector2(size.x, y + 41), Color("392516"), 3)
			for i in range(7):
				var points := PackedVector2Array()
				for j in range(18):
					points.append(Vector2(j * size.x / 17.0, y + 12 + i * 4 + sin(j * 1.8 + i) * 1.5))
				draw_polyline(points, Color(0.23, 0.13, 0.06, 0.3), 1, true)
			for x in [12.0, size.x - 38]:
				draw_rect(Rect2(x, y + 4, 25, 33), Color("383832"))
				for dy in [10.0, 29.0]:
					draw_circle(Vector2(x + 12, y + dy), 3, Color("b19771"))


class ShelfProduct extends Button:
	var selected := false
	var shadow_width := 48.0
	var art: TextureRect
	var tag: PaperSurface
	var hover_tween: Tween
	func _has_point(point: Vector2) -> bool:
		# Upper blank margins must not steal clicks from the previous shelf's tag.
		return Rect2(0, 72, size.x, size.y - 72).has_point(point)
	func _ready() -> void:
		mouse_entered.connect(_refresh)
		mouse_exited.connect(_refresh)
		button_down.connect(_refresh)
		button_up.connect(_refresh)
	func _refresh() -> void:
		if art != null:
			art.modulate = Color(1.04, 1.03, 1.0) if is_hovered() else Color.WHITE
			var target := Vector2.ONE * (1.025 if is_hovered() else 1.0)
			if hover_tween != null and hover_tween.is_valid():
				hover_tween.kill()
			hover_tween = create_tween()
			hover_tween.tween_property(art, "scale", target, 0.15)
		if tag != null:
			tag.marked = selected
			tag.modulate = Color(1.05, 1.03, 0.99) if is_hovered() else Color.WHITE
			tag.queue_redraw()
		queue_redraw()
	func _draw() -> void:
		# A contact shadow grounds the transparent object on the shelf.
		var points := PackedVector2Array()
		for i in range(24):
			var angle := TAU * i / 24.0
			points.append(Vector2(size.x / 2 + cos(angle) * shadow_width, 255 + sin(angle) * 4))
		draw_colored_polygon(points, Color(0.09, 0.05, 0.02, 0.24))


func _ready() -> void:
	SaloonAudio.acquire_scene(self,"shop")
	mouse_filter = MOUSE_FILTER_STOP
	supplies = get_node_or_null("/root/Supplies")
	wallet = get_node_or_null("/root/SlotWallet")
	clock = get_node_or_null("/root/TimeManager")
	_build()
	resized.connect(_fit_canvas)
	_fit_canvas()
	if supplies != null and supplies.has_signal("shop_changed"):
		supplies.connect("shop_changed", _shop_changed)
	elif supplies != null and supplies.has_signal("changed"):
		supplies.connect("changed", _shop_changed)
	if wallet != null:
		wallet.connect("balance_changed", _balance_changed)
	if clock != null:
		clock.connect("time_changed", _time_changed)
	_load_category()
	_balance_changed(_wallet_balance())
	_time_changed(0, 0)
	_update_harbor_lighting()


func _process(delta: float) -> void:
	_update_harbor_lighting()
	if toast_remaining > 0:
		toast_remaining = maxf(0, toast_remaining - delta)
		toast.visible = toast_remaining > 0


func _update_harbor_lighting() -> void:
	if harbor_lighting == null or clock == null:
		return
	# Fractional game minutes also cover pauses, midnight, and opening fast forward.
	harbor_lighting.update_lighting(float(clock.call("visual_minutes")))
	var tint := harbor_lighting.ambient_tint
	if merchant_portrait != null:
		merchant_portrait.self_modulate = tint
	for button: ShelfProduct in slot_buttons:
		if button.art != null:
			# Hover owns modulate; lighting has its own factor and preserves alpha.
			button.art.self_modulate = tint
	if receipt_icon != null:
		receipt_icon.self_modulate = tint


func _fit_canvas() -> void:
	if canvas == null:
		return
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	canvas.scale = Vector2.ONE * factor
	canvas.position = (size - DESIGN_SIZE * factor) / 2


func _label(parent: Node, rect: Rect2, value: String, font_size := 20, color := CREAM) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = value
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	if font_size >= 19:
		label.add_theme_font_override("font", get_theme_font("font", "Button"))
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label


func _button(parent: Node, rect: Rect2, text: String, action: Callable, paper := false) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = text
	button.focus_mode = FOCUS_NONE
	button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 22)
	if paper:
		for style in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		button.add_theme_color_override("font_color", INK)
		button.add_theme_color_override("font_hover_color", Color("875123"))
		button.add_theme_color_override("font_pressed_color", Color("ab682a"))
		button.add_theme_color_override("font_disabled_color", Color(0.31, 0.2, 0.11, 0.32))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _paper(parent: Node, rect: Rect2, dark := false, hanging := false) -> PaperSurface:
	var paper := PaperSurface.new()
	paper.position = rect.position
	paper.size = rect.size
	paper.dark = dark
	paper.hanging = hanging
	paper.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(paper)
	return paper


func _texture(parent: Node, rect: Rect2, texture: Texture2D) -> TextureRect:
	var image := TextureRect.new()
	image.position = rect.position
	image.size = rect.size
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image


func _optional_art(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _build() -> void:
	var surround := ColorRect.new()
	surround.color = Color("171e20")
	surround.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surround.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(surround)
	canvas = Control.new()
	canvas.name = "Canvas"
	canvas.size = DESIGN_SIZE
	canvas.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(canvas)
	var background := _optional_art(BACKGROUND_PATH)
	if background != null:
		harbor_lighting = HARBOR_DAY_NIGHT.new()
		harbor_lighting.name = "HarborBackground"
		harbor_lighting.size = DESIGN_SIZE
		harbor_lighting.mouse_filter = MOUSE_FILTER_IGNORE
		canvas.add_child(harbor_lighting)
	else:
		var backdrop := ColorRect.new()
		backdrop.size = DESIGN_SIZE
		backdrop.color = Color("58868d")
		backdrop.mouse_filter = MOUSE_FILTER_IGNORE
		canvas.add_child(backdrop)
		_paper(canvas, Rect2(695, 163, 882, 593), true)
		_paper(canvas, Rect2(0, 762, 1600, 138), true)
	var merchant := _optional_art(MERCHANT_PATH)
	if merchant != null:
		var portrait := _texture(canvas, Rect2(55, 119, 644, 790), merchant)
		merchant_portrait = portrait
		portrait.name = "Merchant"
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var interaction := MerchantInteraction.new()
		interaction.name = "MerchantInteraction"
		interaction.position = portrait.position
		interaction.size = portrait.size
		interaction.portrait_alpha = merchant.get_image()
		if interaction.portrait_alpha.is_compressed():
			interaction.portrait_alpha.decompress()
		interaction.visible_height = 742 - portrait.position.y
		interaction.focus_mode = FOCUS_NONE
		interaction.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			interaction.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		interaction.pressed.connect(_next_merchant_line)
		canvas.add_child(interaction)
		# A clipped copy of the full painting keeps the foreground's UV coordinates
		# identical to the background for all four sampler textures in the shader.
		if background != null:
			var counter_clip := Control.new()
			counter_clip.name = "CounterClip"
			counter_clip.position = Vector2(0, 742)
			counter_clip.size = Vector2(703, 158)
			counter_clip.clip_contents = true
			counter_clip.mouse_filter = MOUSE_FILTER_IGNORE
			canvas.add_child(counter_clip)
			var counter := _texture(counter_clip, Rect2(Vector2(0, -742), DESIGN_SIZE), harbor_lighting.texture)
			counter.name = "CounterForeground"
			counter.stretch_mode = TextureRect.STRETCH_SCALE
			counter.material = harbor_lighting.material
	_paper(canvas, Rect2(17, 16, 1566, 69), true)
	var back := _button(canvas, Rect2(31, 27, 182, 46), "← 回酒馆", func(): close_requested.emit(), true)
	back.name = "BackButton"
	back.add_theme_font_size_override("font_size", 24)
	back.add_theme_color_override("font_color", CREAM)
	back.add_theme_color_override("font_hover_color", Color("fff0cb"))
	var title := _label(canvas, Rect2(540, 19, 520, 62), "港口货栈", 37)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label = _label(canvas, Rect2(239, 31, 275, 37), "", 22, Color("e1cbaa"))
	balance_label = _label(canvas, Rect2(1260, 24, 286, 50), "", 28)
	balance_label.name = "BalanceLabel"
	balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_paper(canvas, Rect2(713, 107, 349, 57), false, true)
	var goods_title := _label(canvas, Rect2(731, 110, 313, 48), "今日货品", 31, INK)
	goods_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for i in range(CATEGORIES.size()):
		var x := 1081 + i * 165
		var paper := _paper(canvas, Rect2(x, 109, 156, 55), false, true)
		var tab := _button(canvas, Rect2(x + 4, 112, 148, 47), CATEGORIES[i], _set_category.bind(CATEGORIES[i]), true)
		tab.add_theme_font_size_override("font_size", 25)
		tab.name = "Category_" + CATEGORIES[i]
		tab.set_meta("paper", paper)
		category_buttons.append(tab)
	var rack := ShelfRack.new()
	rack.position = Vector2(708, 174)
	rack.size = Vector2(866, 570)
	rack.mouse_filter = MOUSE_FILTER_IGNORE
	if background == null:
		canvas.add_child(rack)
	else:
		rack.free()
	shelves = Control.new()
	shelves.name = "ShelfProducts"
	shelves.position = SHELF_ORIGIN
	shelves.size = Vector2(829, 578)
	shelves.mouse_filter = MOUSE_FILTER_IGNORE
	canvas.add_child(shelves)
	_paper(canvas, Rect2(861, 697, 567, 47))
	previous_button = _button(canvas, Rect2(869, 699, 152, 43), "← 上一页", _turn_page.bind(-1), true)
	previous_button.name = "PreviousPage"
	previous_button.add_theme_font_size_override("font_size", 23)
	page_label = _label(canvas, Rect2(1024, 701, 241, 38), "", 24, INK)
	page_label.name = "PageLabel"
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next_button = _button(canvas, Rect2(1267, 699, 152, 43), "下一页 →", _turn_page.bind(1), true)
	next_button.name = "NextPage"
	next_button.add_theme_font_size_override("font_size", 23)
	_build_receipt()
	_paper(canvas, Rect2(50, 805, 584, 70))
	merchant_line = _label(canvas, Rect2(70, 813, 546, 50), MERCHANT_LINES[0], 21, INK)
	merchant_line.name = "MerchantLine"
	merchant_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast = _label(canvas, Rect2(65, 765, 563, 33), "", 22)
	toast.add_theme_color_override("font_shadow_color", Color("241a12"))
	toast.add_theme_constant_override("shadow_offset_y", 2)
	toast.add_theme_constant_override("shadow_offset_x", 1)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.visible = false


func _build_receipt() -> void:
	_paper(canvas, Rect2(711, 748, 863, 138))
	receipt_icon = _texture(canvas, Rect2(733, 765, 55, 101), null)
	receipt_icon.name = "ReceiptIcon"
	receipt_name = _label(canvas, Rect2(807, 752, 466, 39), "", 27, INK)
	receipt_name.name = "SelectedName"
	receipt_capacity = _label(canvas, Rect2(807, 791, 466, 28), "", 20, Color("654322"))
	receipt_capacity.name = "CapacityLabel"
	receipt_stock = _label(canvas, Rect2(807, 819, 466, 29), "", 21, INK)
	receipt_stock.name = "StockLabel"
	receipt_hint = _label(canvas, Rect2(807, 850, 466, 27), "", 18, Color("75502c"))
	receipt_hint.name = "UnlockHint"
	quantity_controls = Control.new()
	quantity_controls.position = Vector2(1291, 791)
	quantity_controls.size = Vector2(255, 43)
	quantity_controls.mouse_filter = MOUSE_FILTER_IGNORE
	canvas.add_child(quantity_controls)
	minus_button = _button(quantity_controls, Rect2(0, 0, 64, 43), "−", _change_quantity.bind(-1), true)
	minus_button.name = "QuantityMinus"
	minus_button.add_theme_font_size_override("font_size", 30)
	quantity_label = _label(quantity_controls, Rect2(66, 0, 123, 43), "1", 25, INK)
	quantity_label.name = "QuantityLabel"
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plus_button = _button(quantity_controls, Rect2(191, 0, 64, 43), "+", _change_quantity.bind(1), true)
	plus_button.name = "QuantityPlus"
	plus_button.add_theme_font_size_override("font_size", 30)
	receipt_total = _label(canvas, Rect2(1284, 754, 268, 34), "", 24, INK)
	receipt_total.name = "TotalLabel"
	receipt_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	buy_button = _button(canvas, Rect2(1291, 833, 255, 45), "购买", _purchase)
	buy_button.set_meta("custom_audio",true)
	buy_button.name = "BuyButton"
	buy_button.add_theme_font_size_override("font_size", 25)
	# Keep the theme's wood/brass button without its large vertical content margins.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := buy_button.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		buy_button.add_theme_stylebox_override(state, style)


func _next_merchant_line() -> void:
	merchant_line_index = (merchant_line_index + 1) % MERCHANT_LINES.size()
	merchant_line.text = MERCHANT_LINES[merchant_line_index]


func _set_category(value: String) -> void:
	if value == category:
		return
	_cancel_page_turn()
	category = value
	page = 0
	packages = 1
	selected_id = ""
	_load_category()


func _load_category() -> void:
	products = supplies.call("list_shop_items", category) if supplies != null and supplies.has_method("list_shop_items") else catalog.list_items(category)
	page = clampi(page, 0, maxi(0, _page_count() - 1))
	if not _contains_id(selected_id):
		selected_id = str(products[0].id) if not products.is_empty() else ""
	for i in range(category_buttons.size()):
		var paper: PaperSurface = category_buttons[i].get_meta("paper")
		paper.marked = CATEGORIES[i] == category
		paper.queue_redraw()
	_render_shelves()
	_update_receipt()


func _contains_id(id: String) -> bool:
	for item: Dictionary in products:
		if str(item.id) == id:
			return true
	return false


func _selected_item() -> Dictionary:
	for item: Dictionary in products:
		if str(item.id) == selected_id:
			return item
	return {}


func _page_count() -> int:
	return maxi(1, ceili(products.size() / 6.0))


func _turn_page(direction: int) -> void:
	if page_turning:
		return
	var next_page := clampi(page + direction, 0, _page_count() - 1)
	if next_page == page:
		return
	page_turning = true
	_update_page_controls()
	_update_receipt()
	for button in slot_buttons:
		button.disabled = true
	shelf_tween = create_tween()
	shelf_tween.set_parallel(true)
	shelf_tween.tween_property(shelves, "modulate:a", 0.0, 0.12)
	shelf_tween.tween_property(shelves, "position:x", SHELF_ORIGIN.x - direction * 18, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	shelf_tween.chain().tween_callback(_commit_page_turn.bind(next_page, direction))
	shelf_tween.chain().tween_property(shelves, "modulate:a", 1.0, 0.20)
	shelf_tween.parallel().tween_property(shelves, "position:x", SHELF_ORIGIN.x, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	shelf_tween.chain().tween_callback(_finish_page_turn)


func _commit_page_turn(next_page: int, direction: int) -> void:
	page = next_page
	# Keep the purchase line tied to an item visible on the new shelf.
	var first := page * 6
	if first < products.size():
		selected_id = str(products[first].id)
	packages = 1
	_render_shelves()
	shelves.position.x = SHELF_ORIGIN.x + direction * 18
	_update_receipt()


func _finish_page_turn() -> void:
	page_turning = false
	shelves.position = SHELF_ORIGIN
	shelves.modulate = Color.WHITE
	for button in slot_buttons:
		button.disabled = false
	_update_page_controls()
	_update_receipt()


func _cancel_page_turn() -> void:
	if shelf_tween != null and shelf_tween.is_valid():
		shelf_tween.kill()
	page_turning = false
	if shelves != null:
		shelves.position = SHELF_ORIGIN
		shelves.modulate = Color.WHITE


func _update_page_controls() -> void:
	page_label.text = "%d / %d" % [page + 1, _page_count()]
	previous_button.disabled = page_turning or page == 0
	next_button.disabled = page_turning or page + 1 >= _page_count()


func _render_shelves() -> void:
	for child in shelves.get_children():
		shelves.remove_child(child)
		child.queue_free()
	slot_buttons.clear()
	for i in range(6):
		var index := page * 6 + i
		if index >= products.size():
			continue
		var item: Dictionary = products[index]
		var button := ShelfProduct.new()
		button.set_meta("custom_audio",true)
		button.name = "Product_" + str(item.id)
		button.position = Vector2((i % 3) * 276, floori(i / 3.0) * 252)
		button.size = Vector2(258, 319)
		button.disabled = page_turning
		button.focus_mode = FOCUS_NONE
		button.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		button.tooltip_text = str(item.name)
		for style in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		button.pressed.connect(_select_item.bind(str(item.id)))
		shelves.add_child(button)
		var display_height := _display_height(item)
		var product_texture := catalog.get_texture(str(item.id))
		button.art = _texture(button, Rect2(25, 256 - display_height, 208, display_height), product_texture)
		button.art.pivot_offset = Vector2(104, display_height)
		if product_texture != null:
			button.shadow_width = clampf(product_texture.get_width() * display_height / maxf(product_texture.get_height(), 1) * 0.3, 18, 52)
		button.tag = _paper(button, Rect2(3, 248, 252, 70), false, true)
		button.tag.underline = false
		var name_label := _label(button, Rect2(15, 250, 228, 33), _shelf_name(item), 23, INK)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var price := _unit_price(item)
		var price_text := "%d 金币" % price if price >= 0 else "待售"
		if item.storage_mode == "permanent" and bool(_state(str(item.id)).get("owned", false)):
			price_text = "已购置"
		var price_label := _label(button, Rect2(17, 283, 224, 30), price_text, 20, INK)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.selected = str(item.id) == selected_id
		button._refresh()
		slot_buttons.append(button)
	_update_page_controls()
	_update_harbor_lighting()


func _shelf_name(item: Dictionary) -> String:
	var aliases := {"sku_maraschino": "樱桃利口酒", "sku_angostura_bitters": "芳香苦精", "sku_sweet_red_vermouth": "甜红味美思"}
	return str(aliases.get(str(item.id), item.name))


func _display_height(item: Dictionary) -> float:
	if str(item.category) == "装饰品":
		return 116.0
	var heights := {"sku_angostura_bitters": 144.0, "sku_vodka": 172.0, "sku_tequila": 165.0,
		"sku_rye_whiskey": 158.0, "sku_mint_leaf": 98.0, "sku_white_cane_sugar": 126.0,
		"tool_jigger": 132.0, "tool_strainer": 153.0, "tool_shaker": 190.0}
	return float(heights.get(str(item.id), 192.0))


func _select_item(id: String) -> void:
	if page_turning:
		return
	selected_id = id
	SaloonAudio.ui.product(_selected_item())
	packages = 1
	for button: ShelfProduct in slot_buttons:
		button.selected = button.name == "Product_" + id
		button._refresh()
	_update_receipt()


func _state(id: String) -> Dictionary:
	return supplies.call("get_state", id) if supplies != null and supplies.has_method("get_state") else {}


func _unit_price(item: Dictionary) -> int:
	if supplies != null and supplies.has_method("get_unit_price"):
		return int(supplies.call("get_unit_price", str(item.id)))
	return int(item.get("shop_price", -1))


func _change_quantity(change: int) -> void:
	if page_turning:
		return
	packages = clampi(packages + change, 1, 99)
	_update_receipt()


func _update_receipt() -> void:
	var item := _selected_item()
	if item.is_empty():
		receipt_name.text = "这一层暂时没有货品"
		receipt_stock.text = "等下一艘船带来新货。"
		receipt_capacity.text = ""
		receipt_hint.text = ""
		receipt_icon.texture = null
		receipt_total.text = ""
		quantity_controls.visible = false
		buy_button.disabled = true
		return
	var state := _state(selected_id)
	var permanent := str(item.storage_mode) == "permanent"
	var owned := permanent and bool(state.get("owned", false))
	if permanent:
		packages = 1
	receipt_name.text = str(item.name)
	receipt_icon.texture = catalog.get_texture(selected_id)
	quantity_controls.visible = not permanent
	minus_button.disabled = page_turning or packages <= 1
	plus_button.disabled = page_turning or packages >= 99
	var unit := str(item.get("quantity_unit", "件"))
	quantity_label.text = "%d %s" % [packages, unit if str(item.storage_mode) == "container" else "包"]
	if permanent:
		receipt_capacity.text = "酒馆已配备"
		receipt_stock.text = "已在你的酒馆里" if owned else "购置后可一直使用"
	elif str(item.storage_mode) == "container":
		var capacity := float(item.get("package", {}).get("container_capacity", 0))
		var measure := str(item.get("measurement_unit", "ml"))
		receipt_capacity.text = "每%s %s %s" % [unit, _amount(capacity), measure]
		receipt_stock.text = "库存 %d %s  ·  当前%s余 %s %s" % [int(state.get("quantity", 0)), unit, unit, _amount(float(state.get("current_remaining", 0))), measure]
	else:
		var amount := int(item.get("package", {}).get("purchase_quantity", 1))
		receipt_capacity.text = "每包 %d %s" % [amount, unit]
		receipt_stock.text = "库存 %d %s" % [int(state.get("quantity", 0)), unit]
	receipt_hint.text = "首次买入后点亮材料" if not bool(state.get("unlocked", false)) and not permanent else ""
	var price := _unit_price(item)
	var total := maxi(0, price) * packages
	var quote: Dictionary = {}
	if supplies != null and supplies.has_method("quote_purchase"):
		quote = supplies.call("quote_purchase", selected_id, packages)
		total = int(quote.get("total", total))
	receipt_total.text = "合计 %d 金币" % total if price >= 0 else ""
	buy_button.text = "已购置" if owned else "购买"
	buy_button.disabled = page_turning or owned or supplies == null or wallet == null or price < 0 or total > _wallet_balance() or (not quote.is_empty() and not bool(quote.get("ok", false)))
	if not owned and price >= 0 and total > _wallet_balance():
		receipt_hint.text = "还差 %d 金币" % (total - _wallet_balance())
	buy_button.tooltip_text = str(quote.get("message", "")) if buy_button.disabled else ""


func _amount(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, round(value)) else ("%.1f" % value)


func _purchase() -> void:
	if buy_button.disabled or supplies == null or selected_id.is_empty():
		return
	var item := _selected_item()
	var bought := packages
	var balance_before := _wallet_balance()
	if bool(supplies.call("purchase", selected_id, packages)):
		SaloonAudio.ui.product(item,true)
		merchant_line.text = "给你收好了。下回缺什么，再来找我。"
		_show_toast("已买入 %s%s" % [str(item.name), " × %d" % bought if bought > 1 else ""])
		_load_category()
		_show_purchase_feedback(maxi(0, balance_before - _wallet_balance()))
	else:
		SaloonAudio.ui.play("click")
		var message := str(supplies.get("last_error"))
		_show_toast(message if not message.is_empty() else "这笔没买成，稍后再试。")
		_update_receipt()


func _show_purchase_feedback(spent: int) -> void:
	if spent <= 0:
		return
	# Each success owns a short-lived layer, so another purchase can start at once.
	while purchase_feedback_layers.size() >= 3:
		var oldest: Control = purchase_feedback_layers.pop_front()
		oldest.queue_free()
	purchase_feedback_sequence += 1
	var feedback := Control.new()
	feedback.name = "PurchaseFeedback_%d" % purchase_feedback_sequence
	feedback.size = DESIGN_SIZE
	feedback.mouse_filter = MOUSE_FILTER_IGNORE
	feedback.z_index = 20
	canvas.add_child(feedback)
	purchase_feedback_layers.append(feedback)
	var origin := buy_button.position + Vector2(buy_button.size.x * 0.5, 5)
	var spread := [Vector2(-52, -50), Vector2(-27, -72), Vector2(0, -81), Vector2(30, -68), Vector2(54, -45)]
	for i in range(spread.size()):
		var coin := PurchaseCoin.new()
		coin.name = "PurchaseCoin_%d" % i
		coin.size = Vector2.ONE * (22.0 if i % 2 == 0 else 25.0)
		coin.pivot_offset = coin.size * 0.5
		coin.position = origin - coin.pivot_offset + Vector2((i - 2) * 3, 0)
		coin.rotation = (i - 2) * 0.08
		coin.mouse_filter = MOUSE_FILTER_IGNORE
		feedback.add_child(coin)
		var peak: Vector2 = coin.position + spread[i]
		var motion := coin.create_tween().set_parallel(true)
		motion.tween_property(coin, "position", peak, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		motion.tween_property(coin, "position", peak + Vector2((i - 2) * 5, 17), 0.42).from(peak).set_delay(0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		motion.tween_property(coin, "rotation", coin.rotation + (i - 2) * 0.24, 0.76)
		motion.tween_property(coin, "modulate:a", 0.0, 0.34).set_delay(0.42)
	# The header gap beside the balance leaves the receipt and quantity readable.
	var spent_label := _label(feedback, Rect2(1067, 29, 187, 42), "−%d 金币" % spent, 24, Color("ffe1a0"))
	spent_label.name = "PurchaseSpendLabel"
	spent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spent_label.add_theme_color_override("font_shadow_color", INK)
	spent_label.add_theme_constant_override("shadow_offset_y", 2)
	spent_label.add_theme_constant_override("shadow_offset_x", 1)
	# Replace an older caption during fast buying; the latest amount stays clear.
	for layer in purchase_feedback_layers:
		if layer != feedback:
			var previous := layer.get_node_or_null("PurchaseSpendLabel") as Label
			if previous != null:
				previous.visible = false
	var caption_motion := spent_label.create_tween().set_parallel(true)
	caption_motion.tween_property(spent_label, "position:y", spent_label.position.y - 17, 0.90).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	caption_motion.tween_property(spent_label, "modulate:a", 0.0, 0.35).set_delay(0.55)
	if balance_feedback_tween != null and balance_feedback_tween.is_valid():
		balance_feedback_tween.kill()
	balance_label.modulate = Color(1.22, 1.12, 0.96)
	balance_feedback_tween = balance_label.create_tween()
	balance_feedback_tween.tween_property(balance_label, "modulate", Color.WHITE, 0.75)
	var cleanup := feedback.create_tween()
	cleanup.tween_interval(0.95)
	cleanup.tween_callback(func():
		purchase_feedback_layers.erase(feedback)
		feedback.queue_free())


func _shop_changed() -> void:
	# An external stock/balance update cancels the leaf before rebuilding its goods.
	_cancel_page_turn()
	_load_category()


func _balance_changed(value: int) -> void:
	balance_label.text = "金币  %d" % value
	_update_receipt()


func _wallet_balance() -> int:
	return int(wallet.get("balance")) if wallet != null else 0


func _time_changed(_day: int, _minute: int) -> void:
	if clock != null:
		time_label.text = "%s  ·  %s" % [clock.call("formatted_day"), clock.call("formatted_time")]


func _show_toast(message: String) -> void:
	toast.text = message
	toast.visible = true
	toast_remaining = 4.0


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_requested.emit()

## Optional deep link from a depleted workbench ingredient. Does not buy anything.
func focus_item(id: String) -> bool:
	var item: Dictionary=catalog.get_item(id)
	if item.is_empty() or item.category not in CATEGORIES: return false
	_cancel_page_turn()
	category=item.category
	page=0
	packages=1
	selected_id=id
	_load_category()
	for i in range(products.size()):
		if products[i].id==id:
			page=i/6
			_render_shelves()
			_update_receipt()
			return true
	return false
