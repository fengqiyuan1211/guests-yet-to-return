extends RefCounted
const FONT = preload("res://assets/fonts/NotoSerifSC.ttf")
const INK = Color("f4e7cb")
static func label(parent: Node, rect: Rect2, text: String, px := 26, color := INK) -> Label:
	var node := Label.new()
	node.position=rect.position
	node.size=rect.size
	node.text=text
	node.add_theme_font_override("font",FONT)
	node.add_theme_font_size_override("font_size",px)
	node.add_theme_color_override("font_color",color)
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node
static func button(parent: Node, rect: Rect2, text: String, action: Callable, small := false) -> Button:
	var node := Button.new()
	node.position=rect.position
	node.size=rect.size
	node.text=text
	node.add_theme_font_override("font",FONT)
	node.add_theme_font_size_override("font_size",21 if small else 29)
	node.add_theme_color_override("font_color",INK)
	node.add_theme_color_override("font_hover_color",Color("ffe0a0"))
	node.add_theme_color_override("font_focus_color",Color("ffe0a0"))
	node.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for key in ["normal","hover","pressed","focus"]:
		var box:=StyleBoxFlat.new()
		box.bg_color=Color(.07,.12,.16,.4 if small else .08)
		box.border_color=Color("d9b477")
		box.border_width_bottom=2 if key!="normal" else 0
		box.set_corner_radius_all(3)
		node.add_theme_stylebox_override(key,box)
	node.pressed.connect(action)
	parent.add_child(node)
	return node
static func panel(parent: Node, rect: Rect2) -> Panel:
	var node:=Panel.new()
	node.position=rect.position
	node.size=rect.size
	var box:=StyleBoxFlat.new()
	box.bg_color=Color(.055,.085,.105,.94)
	box.border_color=Color("af8b56")
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	node.add_theme_stylebox_override("panel",box)
	parent.add_child(node)
	return node
