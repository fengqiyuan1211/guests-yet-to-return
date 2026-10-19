extends RefCounted
## Display aliases keep practice-session IDs independent of shared catalogue/SKU IDs.
## B sprites are visual overrides; original trimmed art remains the fallback.
const ROOT := "res://assets/workbench/"
const SHARED_ROOT := "res://assets/art/supplies/textures/"
const CELLS := {
	"shaker": "shaker_body", "lid": "shaker_strainer_top", "cap": "shaker_cap",
	"jigger": "jigger", "mixing": "mixing_glass", "coupe": "saucer_glass",
	"highball": "highball_glass", "spoon": "bar_spoon", "strainer": "strainer", "muddler": "muddler",
	"gin": "gin_london_dry", "rum": "white_rum", "vodka": "vodka",
	"lime": "lime_juice", "syrup": "simple_syrup", "soda": "soda_water",
	"garnish": "lime_wedge", "lemon_slice":"lemon_slice", "cube": "standard_cube", "crushed": "crushed_ice"
}
static var cache: Dictionary = {}
static var catalog=preload("res://scripts/supply_catalog.gd").new()

static func texture(id: String) -> Texture2D:
	var pixel: Texture2D=preload("res://scripts/pixel_art.gd").sprite(str(CELLS.get(id,id)).trim_prefix("glass_"))
	if pixel!=null: return pixel
	if cache.has(id):
		return cache[id]
	if not CELLS.has(id):
		var item: Dictionary=catalog.get_item(id)
		if item.is_empty(): return null
		cache[id]=load(item.texture_resource_path)
		return cache[id]
	var path: String = SHARED_ROOT + CELLS[id] + ".tres"
	if not ResourceLoader.exists(path):
		return null
	var shared := load(path) as Texture2D
	cache[id] = shared
	return shared
