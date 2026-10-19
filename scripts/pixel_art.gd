extends RefCounted
## Visual-only B palette. No catalogue IDs, recipe values or save data are rewritten.
const ROOT := "res://assets/pixel_b/"
const CAMEOS := ["stick", "yellow_creature"]
const PEOPLE := ["harbor_merchant", "hank", "ada", "milo"]
const GLASSES := ["mixing_glass", "highball_glass", "cocktail_glass", "balloon_glass", "saucer_glass"]
static var cache: Dictionary = {}

static func sprite(id: String) -> Texture2D:
	id=id.trim_prefix("sku_").trim_prefix("tool_").trim_prefix("glass_")
	if id=="shaker": id="shaker_body"
	var path := ROOT+"sprites/"+id+(".svg" if id in GLASSES else ".tres")
	var refined := ROOT+"v2/"+id+".tres"
	if ResourceLoader.exists(refined): path=refined
	# Approved fine-pixel tools/bottles. Other art keeps its existing version.
	var workbench_refined := ROOT+"v3/"+id+".tres"
	if ResourceLoader.exists(workbench_refined): path=workbench_refined
	# Full portraits use approved C art; journal_avatar keeps its separate Q sheet.
	if id in PEOPLE:
		var portrait_path := ROOT+"characters_c/"+id+".tres"
		if ResourceLoader.exists(portrait_path): path=portrait_path
	if not ResourceLoader.exists(path): return null
	if not cache.has(path): cache[path]=load(path)
	return cache[path]

static func journal_avatar(profile: Dictionary) -> Texture2D:
	# Journal list uses the approved chibi sheet, independently of scene portraits.
	var id := str(profile.get("id", ""))
	if id in PEOPLE:
		var path := ROOT+"sprites/"+id+".tres"
		if not cache.has(path): cache[path]=load(path)
		return cache[path]
	return person(profile,true)

static func person(profile: Dictionary, head_only := false) -> Texture2D:
	var id := str(profile.get("id", ""))
	if id in PEOPLE:
		var full := sprite(id)
		if not head_only: return full
		var face := AtlasTexture.new()
		face.atlas=full
		face.region=Rect2(full.get_size()*Vector2(.20,.01),full.get_size()*Vector2(.65,.37))
		face.filter_clip=true
		return face
	# Cameos retain their original source and original portrait crop.
	var source := load(str(profile.texture)) as Texture2D
	if not head_only: return source
	var crop := AtlasTexture.new()
	crop.atlas=source
	var r: Array=profile.portrait
	crop.region=Rect2(r[0],r[1],r[2],r[3])
	crop.filter_clip=true
	return crop

static func scene(id: String) -> Texture2D:
	var path := ROOT+"scenes/"+id+".tres"
	if not ResourceLoader.exists(path): return null
	# Draw commands retain RIDs, not the temporary Resource returned by load().
	if not cache.has(path): cache[path]=load(path)
	return cache[path]

static func texture(path: String) -> Texture2D:
	if path.contains("harbor-merchant"): return sprite("harbor_merchant")
	if path.contains("saloon-"): return load(preload("res://scripts/saloon_composition.gd").BACKGROUND_PATH)
	if path.contains("harbor-shop-"): return load(ROOT+"shop.png")
	if path.contains("workbench/background"): return load(preload("res://scripts/saloon_composition.gd").BACKGROUND_PATH)
	if path.contains("research-desk"): return load(ROOT+"v2/research.png")
	if path.contains("journal-paper"): return load(ROOT+"paper.svg")
	if path.contains("art/opening/"):
		var id := path.get_file().get_basename()
		if id.begins_with("harbor-"): return load(ROOT+"harbor.png")
		if id=="city-bar": id="city-bar-faceless"
		var replacement := scene(id)
		if replacement!=null: return replacement
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
