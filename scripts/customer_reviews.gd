extends Control
signal close_requested
const PAPER := preload("res://assets/codex/journal-paper-v1.png")
var surface: Control

func _ready() -> void:
	surface = Control.new()
	add_child(surface)
	var paper := TextureRect.new()
	paper.texture = PAPER
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.position = Vector2(275, 65)
	paper.size = Vector2(1130, 770)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(paper)
	var heading := Label.new()
	heading.text = "客人的留言"
	heading.position = Vector2(325, 100)
	heading.add_theme_font_size_override("font_size", 34)
	heading.add_theme_color_override("font_color", Color("593d29"))
	surface.add_child(heading)
	var close := Button.new()
	close.text = "返回酒馆"
	close.position = Vector2(1170, 103)
	close.size = Vector2(175, 48)
	close.add_theme_font_size_override("font_size", 22)
	close.pressed.connect(func(): close_requested.emit())
	surface.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(325, 175)
	scroll.size = Vector2(1015, 610)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	surface.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 22)
	scroll.add_child(column)
	var records: Array = CustomerService.state.deliveries.values()
	records.reverse()
	if records.is_empty(): _label(column, "还没有客人留下评价。", 24)
	var guests: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/guests.json"))
	for record in records:
		if record.status != "settled": continue
		var guest_name := "来客"
		for guest in guests:
			if guest.id == record.guest_id and StoryDialogue.is_known(str(guest.id)): guest_name = guest.name
		var stars := "尚未留下评分"
		if record.review.get("stars") != null:
			stars = "★".repeat(int(record.review.stars)) + "☆".repeat(5 - int(record.review.stars))
		_label(column, "%s   %s   第%d天" % [guest_name, stars, int(record.day)], 24)
		_label(column, "%s    收入 %d 金币" % [record.recipe_name, int(record.amount)], 19)
		var messages: Array = record.feedback.get("messages", [])
		var said := "客人收下了这一杯。"
		for message in messages:
			if message.speaker == "guest":
				said = str(message.text)
				break
		_label(column, said, 23)
		var separator := HSeparator.new()
		column.add_child(separator)
	resized.connect(_fit)
	_fit()

func _label(parent: Node, text: String, px: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("593d29"))
	label.add_theme_font_size_override("font_size", px)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)

func _fit() -> void:
	var factor := minf(size.x / 1600, size.y / 900)
	surface.scale = Vector2.ONE * factor
	surface.position = (size - Vector2(1600, 900) * factor) * 0.5
