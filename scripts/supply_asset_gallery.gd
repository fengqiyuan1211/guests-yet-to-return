extends Control
## Standalone asset review scene, not connected to the game's navigation.

const CatalogScript = preload("res://scripts/supply_catalog.gd")
const FONT = preload("res://assets/fonts/NotoSerifSC.ttf")
var catalog: RefCounted
var grid: GridContainer
var heading: Label
var groups := ["原酒", "配料与装饰", "器具、杯型与冰"]
var current_group := 0
var demo: Node2D
var overlay: Control

func _ready() -> void:
	catalog = CatalogScript.new()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color("332318")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var paper := TextureRect.new()
	paper.texture = load("res://assets/codex/journal-paper-v1.png")
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.modulate = Color(1, 1, 1, 0.15)
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(paper)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	heading = label("酒馆 · 原料与器具素材册", 30, Color("e4c795"))
	column.add_child(heading)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 16)
	column.add_child(tabs)
	for index in range(groups.size()):
		var button := Button.new()
		button.text = groups[index]
		button.add_theme_font_override("font", FONT)
		button.add_theme_font_size_override("font_size", 20)
		button.custom_minimum_size = Vector2(230, 45)
		button.pressed.connect(show_group.bind(index))
		tabs.add_child(button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 6
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 13)
	grid.add_theme_constant_override("v_separation", 13)
	scroll.add_child(grid)
	column.add_child(label("透明底独立素材　·　点击器具或杯型查看摆放、倾斜和液面", 17, Color("bea985")))
	show_group(0)

func label(text: String, size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_override("font", FONT)
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	return result

func show_group(index: int) -> void:
	current_group = index
	heading.text = "酒馆 · " + groups[index] + "素材册"
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var records: Array = []
	if index == 0:
		records = catalog.list_items("原酒")
	elif index == 1:
		records = catalog.list_items("配料") + catalog.list_items("装饰品")
	else:
		for item: Dictionary in catalog.list_items("器材") + catalog.list_items("杯型"):
			for part: Dictionary in item.parts:
				var record: Dictionary = item.duplicate(true)
				record.texture_resource_path = part.texture_resource_path
				if item.id == "tool_shaker":
					record.name = {"shaker_body": "摇壶 · 杯身", "shaker_strainer_top": "摇壶 · 滤盖", "shaker_cap": "摇壶 · 顶盖"}[part.id]
				records.append(record)
		records.append_array(catalog.list_ice())
	for record: Dictionary in records:
		add_card(record, 206 if index == 2 else 290)

func add_card(record: Dictionary, card_height: float) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(236, card_height)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("ebd3a3")
	style.set_corner_radius_all(5)
	style.set_border_width_all(1)
	style.border_color = Color("a17a46")
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", style)
	grid.add_child(panel)
	var contents := VBoxContainer.new()
	panel.add_child(contents)
	var image := TextureRect.new()
	image.texture = load(record.texture_resource_path)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size.y = card_height - 72
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(image)
	var title := label(record.name, 17, Color("4f321e"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	contents.add_child(title)
	var subtitle := label(record.get("category", "制作素材"), 13, Color("916b3f"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	contents.add_child(subtitle)
	if record.has("scene_path"):
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				show_tool(record.id)
		)
		for child in [contents, image, title, subtitle]:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_tool(id: String) -> void:
	close_tool()
	var record: Dictionary = catalog.get_item(id)
	if not record.has("scene_path"):
		return
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = size / 2 - Vector2(430, 310)
	panel.size = Vector2(860, 620)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("eed7aa")
	style.set_border_width_all(3)
	style.border_color = Color("936832")
	style.set_corner_radius_all(7)
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)
	var title := label(record.name, 30, Color("53331f"))
	title.position = Vector2(35, 25)
	panel.add_child(title)
	demo = load(record.scene_path).instantiate()
	demo.position = Vector2(255, 475)
	demo.scale = Vector2(1.25, 1.25)
	panel.add_child(demo)
	var controls := VBoxContainer.new()
	controls.position = Vector2(545, 130)
	controls.size = Vector2(240, 400)
	controls.add_theme_constant_override("separation", 15)
	panel.add_child(controls)
	var actions := [["倾斜 / 复位", func(): demo.set_tilt(0 if absf(demo.rotation_degrees) > 1 else -45)]]
	if not demo.liquid_shape.is_empty():
		actions.append(["加入液体 / 清空", func(): demo.set_fill_ratio(0 if demo.fill_ratio > 0 else 0.65)])
	if record.id == "tool_shaker":
		actions.append(["开盖 / 合盖", func(): demo.set_open(not demo.is_open)])
		actions.append(["摇和", func(): demo.animate_shake()])
	actions.append(["关闭", close_tool])
	for action in actions:
		var button := Button.new()
		button.text = action[0]
		button.add_theme_font_override("font", FONT)
		button.add_theme_font_size_override("font_size", 21)
		button.custom_minimum_size = Vector2(240, 48)
		button.pressed.connect(action[1])
		controls.add_child(button)
	var note := label("空杯与部件可独立操作", 18, Color("916b3f"))
	note.position = Vector2(45, 550)
	panel.add_child(note)

func close_tool() -> void:
	if is_instance_valid(overlay):
		remove_child(overlay)
		overlay.queue_free()
	overlay = null
	demo = null
