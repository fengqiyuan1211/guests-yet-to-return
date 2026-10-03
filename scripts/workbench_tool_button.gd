extends Button
func _make_custom_tooltip(text: String) -> Object:
	if text.strip_edges().is_empty(): return null
	return preload("res://scripts/workbench_tool_help.gd").popup(text)
