extends Control
## Editable decoration lives underneath typeset names and prices.
const PAPER := preload("res://assets/menu/frontier-menu-paper-v1.png")
const CANVAS := preload("res://scripts/menu_drawing_canvas.gd")
var drinks: Array = []
var design: Dictionary = {}
var sample := false
var drawing: Control
var stage: Control

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(_fit)
	rebuild()

func _fit() -> void:
	if is_instance_valid(stage):
		stage.scale = size / Vector2(540, 810)

func _text(rect: Rect2, value: String, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stage.add_child(label)
	return label

func rebuild() -> void:
	if not is_inside_tree():
		return
	var retained: Control = drawing if is_instance_valid(drawing) else null
	if retained != null:
		retained.get_parent().remove_child(retained)
	for node in get_children():
		remove_child(node)
		node.queue_free()
	stage = Control.new()
	stage.size = Vector2(540, 810)
	stage.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(stage)
	_fit()
	var night: bool = design.get("template", "parchment") == "nocturne"
	var ink := Color("ecd4a2") if night else Color("573719")
	var muted := Color("c5a574") if night else Color("977042")
	var paper := TextureRect.new()
	paper.size = Vector2(540, 810)
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.texture = PAPER
	paper.mouse_filter = MOUSE_FILTER_IGNORE
	if night:
		paper.modulate = Color("34231d")
	var art_path: String = design.get("ai_image_path", "")
	if design.get("method") == "ai" and not art_path.is_empty() and FileAccess.file_exists(art_path):
		var artwork := Image.load_from_file(art_path)
		if artwork != null and not artwork.is_empty():
			paper.texture = ImageTexture.create_from_image(artwork)
			paper.modulate = Color.WHITE
	stage.add_child(paper)
	if night:
		var frame := ReferenceRect.new()
		frame.position = Vector2(26, 26)
		frame.size = Vector2(488, 758)
		frame.border_color = Color("b79961")
		frame.border_width = 1.4
		frame.editor_only = false
		frame.mouse_filter = MOUSE_FILTER_IGNORE
		stage.add_child(frame)
	drawing = retained if retained != null else Control.new()
	if retained == null:
		drawing.set_script(CANVAS)
	drawing.size = Vector2(540, 810)
	stage.add_child(drawing)
	if retained == null:
		drawing.set_strokes(design.get("strokes", []))
		drawing.editable = false
	_text(Rect2(50, 72, 440, 26), "T O  T H E  G U E S T S", 14, muted, HORIZONTAL_ALIGNMENT_CENTER)
	var title: String = design.get("title", "今夜酒单")
	_text(Rect2(48, 113, 444, 63), title, 38 if title.length() <= 10 else 26, ink, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Rect2(72, 180, 396, 28), "───────   ◇   ───────", 18, muted, HORIZONTAL_ALIGNMENT_CENTER)
	if drinks.is_empty():
		_text(Rect2(76, 350, 388, 38), "今晚的好酒，等你写下。", 23, muted, HORIZONTAL_ALIGNMENT_CENTER)
	var gap := 74.0
	if drinks.size() <= 4:
		gap = 100.0
	for i in range(mini(drinks.size(), 6)):
		var recipe: Dictionary = drinks[i]
		var y := 238.0 + i * gap
		_text(Rect2(63, y - 2, 25, 28), "%02d" % (i + 1), 13, muted)
		_text(Rect2(101, y - 9, 295, 37), str(recipe.get("name", "")), 25, ink)
		_text(Rect2(397, y - 7, 80, 33), "%d" % int(recipe.get("price", recipe.get("reference_price", 0))), 24, ink, HORIZONTAL_ALIGNMENT_RIGHT)
		var tags: Array = recipe.get("tags", [])
		_text(Rect2(101, y + 30, 365, 24), " · ".join(tags), 14, muted)
		var line := ColorRect.new()
		line.position = Vector2(100, y + 65)
		line.size = Vector2(377, 0.7)
		line.color = Color(muted, 0.32)
		line.mouse_filter = MOUSE_FILTER_IGNORE
		stage.add_child(line)
	_text(Rect2(71, 719, 398, 30), str(design.get("subtitle", "致未归的客人")), 18, ink, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Rect2(71, 751, 398, 24), "20:00 — 04:00  /  金币计价", 12, muted, HORIZONTAL_ALIGNMENT_CENTER)
	if sample:
		_text(Rect2(439, 181, 53, 27), "样张", 14, muted, HORIZONTAL_ALIGNMENT_RIGHT)
