extends RefCounted
## Display aliases keep practice-session IDs independent of shared catalogue/SKU IDs.
## Use fengqiyuan's existing trimmed resources without modifying their source pixels.
const ROOT := "res://assets/workbench/"
const SHARED_ROOT := "res://assets/art/supplies/textures/"
const CELLS := {
	"shaker": "shaker_body", "lid": "shaker_strainer_top", "cap": "shaker_cap",
	"jigger": "jigger", "mixing": "mixing_glass", "coupe": "saucer_glass",
	"highball": "highball_glass", "spoon": "bar_spoon", "strainer": "strainer", "muddler": "muddler",
	"gin": "gin_london_dry", "rum": "white_rum", "vodka": "vodka",
	"lime": "lime_juice", "syrup": "simple_syrup", "soda": "soda_water",
	"garnish": "lime_wedge", "cube": "standard_cube", "crushed": "crushed_ice"
}
static var cache: Dictionary = {}

static func texture(id: String) -> Texture2D:
	if cache.has(id):
		return cache[id]
	if not CELLS.has(id):
		return null
	var path: String = SHARED_ROOT + CELLS[id] + ".tres"
	if not ResourceLoader.exists(path):
		return null
	var shared := load(path) as Texture2D
	cache[id] = shared
	return shared
