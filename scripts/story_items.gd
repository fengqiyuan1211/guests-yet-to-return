extends RefCounted
## Story keepsakes share the atomic research/workbench save; never shop stock.
const PATH := "res://data/minigames/story_items.json"

static func get_item(id: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for item in data.items:
		if item.id == id: return item.duplicate(true)
	return {}

static func get_state(id: String) -> Dictionary:
	return WorkbenchSession.research_state().get("story_items", {}).get(id, {}).duplicate(true)

static func owned_items() -> Array:
	var result: Array = []
	for id in WorkbenchSession.research_state().get("story_items", {}):
		var item := get_item(str(id))
		if not item.is_empty() and get_state(str(id)).get("owned", false): result.append(item)
	return result

static func texture(id: String) -> Texture2D:
	return load(get_item(id).get("image_path", "")) as Texture2D
