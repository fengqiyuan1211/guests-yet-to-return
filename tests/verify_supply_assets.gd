extends Node
## Tests imported art and independent prop scenes; all player saves stay in /tmp.

const CatalogScript := preload("res://scripts/supply_catalog.gd")
var failures: Array[String] = []
var checks := 0
var checked_images: Dictionary = {}
var checked_textures: Dictionary = {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	for name in ["SlotWallet", "StoryDialogue", "GameSession", "MenuCatalog"]:
		var singleton := get_node_or_null("/root/" + name)
		if singleton != null and not str(singleton.save_path).begins_with("/tmp/") and not str(singleton.save_path).begins_with("/private/tmp/"):
			push_error("Run with isolated --slot-wallet, --dialogue-save, --game-save and --menu-save paths")
			get_tree().quit(2)
			return
	get_node("/root/TimeManager").set_process(false)
	get_node("/root/GameSession").set_process(false)
	call_deferred("run")

func run() -> void:
	var catalog := CatalogScript.new()
	check(catalog.last_error.is_empty(), "Supply catalogue loads")
	var ingredients := 0
	var permanent := 0
	for item: Dictionary in catalog.list_items():
		verify_png(str(item.image_path))
		verify_texture(str(item.texture_resource_path), str(item.image_path))
		if item.storage_mode == "permanent":
			permanent += 1
			for part: Dictionary in item.get("parts", []):
				verify_png(str(part.image_path))
				verify_texture(str(part.texture_resource_path), str(part.image_path))
			await verify_prop(item)
		else:
			ingredients += 1
	var ice := catalog.list_ice()
	for item: Dictionary in ice:
		verify_png(str(item.image_path))
		verify_texture(str(item.texture_resource_path), str(item.image_path))
	check(ingredients == 22, "All 22 ingredient product images are checked")
	check(permanent == 10, "All six tool and four glass scenes are checked")
	check(ice.size() == 2, "Both separate ice materials are checked")
	check(checked_images.size() == 36 and checked_textures.size() == 36, "36 unique independent PNGs and AtlasTextures, including three shaker components")
	var audio := get_node("/root/SaloonAudio")
	audio.set_process(false)
	if is_instance_valid(audio.fade):
		audio.fade.kill()
	for player in audio.players:
		player.stop()
		player.stream = null
	audio._streams.clear()
	print("SUPPLY ASSETS: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size(), " (", checks, " checks; ", checked_images.size(), " PNGs; ", permanent, " prop scenes)")
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func verify_png(path: String) -> void:
	if checked_images.has(path):
		return
	checked_images[path] = true
	check(path.begins_with("res://") and path.ends_with(".png") and FileAccess.file_exists(path), "Independent PNG exists: " + path)
	if not FileAccess.file_exists(path):
		return
	var image := Image.new()
	# Decode original bytes only for QA; runtime props use imported textures.
	var error := image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	check(error == OK and not image.is_empty(), "PNG decodes: " + path)
	if error != OK or image.is_empty():
		return
	check(image.get_width() > 0 and image.get_height() > 0, "PNG dimensions are valid: " + path)
	check(image.detect_alpha() != Image.ALPHA_NONE, "PNG contains real transparent pixels: " + path)
	var width := image.get_width()
	var height := image.get_height()
	for corner in [Vector2i.ZERO, Vector2i(width - 1, 0), Vector2i(0, height - 1), Vector2i(width - 1, height - 1)]:
		check(image.get_pixelv(corner).a == 0.0, "PNG canvas corner is transparent: " + path)
	check(image.get_used_rect().has_area(), "PNG contains visible artwork: " + path)

func verify_texture(path: String, image_path: String) -> void:
	if checked_textures.has(path):
		return
	checked_textures[path] = true
	check(FileAccess.file_exists(path) and ResourceLoader.exists(path), "Texture resource exists: " + path)
	if not FileAccess.file_exists(path):
		return
	var texture := load(path) as Texture2D
	check(texture != null, "Texture resource loads: " + path)
	if texture == null:
		return
	check(texture.get_width() > 0 and texture.get_height() > 0, "Texture has visible dimensions: " + path)
	check(texture is AtlasTexture, "Display trimming preserves original PNG through AtlasTexture: " + path)
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		check(atlas.atlas != null and atlas.atlas.resource_path == image_path, "Atlas points to the correct original image: " + path)
		check(atlas.region.has_area() and atlas.region.position.x >= 0 and atlas.region.position.y >= 0, "Atlas region starts inside the source: " + path)
		if atlas.atlas != null:
			check(atlas.region.end.x <= atlas.atlas.get_width() and atlas.region.end.y <= atlas.atlas.get_height(), "Atlas region remains inside source dimensions: " + path)
		check(atlas.filter_clip, "Atlas filtering is clipped to its visible region: " + path)

func verify_prop(item: Dictionary) -> void:
	var path := str(item.get("scene_path", ""))
	check(not path.is_empty() and FileAccess.file_exists(path) and ResourceLoader.exists(path), "Independent prop scene exists: " + item.id)
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var packed := load(path) as PackedScene
	check(packed != null, "Prop scene loads: " + item.id)
	if packed == null:
		return
	var prop := packed.instantiate() as Node2D
	check(prop != null, "Prop scene instantiates as Node2D: " + item.id)
	if prop == null:
		return
	add_child(prop)
	await get_tree().process_frame
	check(str(prop.get("tool_id")) == item.id, "Scene retains canonical product identifier: " + item.id)
	for method in ["set_fill_ratio", "set_tilt", "get_anchor", "drag_to", "set_open", "animate_shake"]:
		check(prop.has_method(method), "Prop exposes reusable interaction method: " + item.id + " " + method)
	var body := prop.get_node_or_null("Body") as Sprite2D
	check(body != null and body.texture != null, "Prop body uses an imported texture: " + item.id)
	var collider := prop.get_node_or_null("HitArea/Shape") as CollisionShape2D
	check(collider != null and collider.shape != null, "Prop has a selectable collision shape: " + item.id)
	prop.call("drag_to", Vector2(400, 380))
	check(prop.global_position.is_equal_approx(Vector2(400, 380)), "Prop can be repositioned: " + item.id)
	prop.call("set_tilt", -45.0)
	check(is_equal_approx(prop.rotation_degrees, -45.0), "Prop can tilt for pouring: " + item.id)
	for anchor_name in ["GrabPoint", "RestPoint", "RimPoint", "PourPoint", "FillPoint", "GarnishPoint"]:
		var marker := prop.get_node_or_null(anchor_name) as Marker2D
		check(marker != null, "Prop has a named anchor: " + item.id + " " + anchor_name)
		if marker != null:
			var actual: Vector2 = prop.call("get_anchor", anchor_name)
			check(actual.is_finite() and actual.is_equal_approx(marker.global_position), "Anchor tracks moved and tilted prop in world coordinates: " + item.id + " " + anchor_name)
	if item.asset_id in ["strainer", "muddler", "bar_spoon"]:
		check(prop.get_node_or_null("WorkingPoint") is Marker2D, "Hand tool has a working tip anchor: " + item.id)
	prop.call("set_tilt", 0.0)
	var liquid := prop.get_node_or_null("Liquid") as Polygon2D
	var shape: PackedVector2Array = prop.get("liquid_shape")
	check(liquid != null, "Prop has an independent liquid overlay: " + item.id)
	prop.call("set_fill_ratio", 0.5, Color("9acda2"))
	check(is_equal_approx(float(prop.get("fill_ratio")), 0.5), "Prop accepts a partial fill ratio: " + item.id)
	if liquid != null and not shape.is_empty():
		check(liquid.visible and liquid.polygon.size() >= 3, "Fillable vessel shows a valid liquid polygon: " + item.id)
		check(liquid.color.is_equal_approx(Color("9acda2")), "Liquid appearance can be supplied by drink controller: " + item.id)
		prop.call("set_fill_ratio", 0.0)
		check(not liquid.visible, "Empty vessel hides liquid overlay: " + item.id)
	prop.call("set_fill_ratio", 2.0)
	check(float(prop.get("fill_ratio")) == 1.0, "Fill ratio is clamped at full: " + item.id)
	prop.call("set_fill_ratio", -0.5)
	check(float(prop.get("fill_ratio")) == 0.0, "Fill ratio is clamped at empty: " + item.id)
	prop.call("set_fill_ratio", NAN)
	check(float(prop.get("fill_ratio")) == 0.0, "Non-finite fill is handled without invalid geometry: " + item.id)
	if item.id == "tool_shaker":
		await verify_shaker(prop, item)
	prop.queue_free()
	await get_tree().process_frame

func verify_shaker(prop: Node2D, item: Dictionary) -> void:
	check(item.parts.size() == 3, "Shaker product names three independent component assets")
	var body := prop.get_node_or_null("Body") as Sprite2D
	var strainer := prop.get_node_or_null("StrainerTop") as Sprite2D
	var cap := prop.get_node_or_null("Cap") as Sprite2D
	check(body != null and strainer != null and cap != null, "Shaker body, strainer top and cap are separate scene sprites")
	if body == null or strainer == null or cap == null:
		return
	check(body.texture != strainer.texture and cap.texture != strainer.texture and body.texture != cap.texture, "Shaker components load distinct independent textures")
	var body_closed := body.position
	var strainer_closed := strainer.position
	var cap_closed := cap.position
	prop.call("set_open", true, false)
	check(bool(prop.get("is_open")) and not strainer.position.is_equal_approx(strainer_closed) and not cap.position.is_equal_approx(cap_closed), "Instant opening moves both removable top parts")
	check(body.position.is_equal_approx(body_closed), "Opening keeps the shaker body in place")
	var rotation_before := prop.rotation
	prop.call("animate_shake")
	await get_tree().create_timer(0.1).timeout
	check(is_equal_approx(prop.rotation, rotation_before), "Open shaker does not start a shake animation")
	prop.call("set_open", false, false)
	check(not bool(prop.get("is_open")) and strainer.position.is_equal_approx(strainer_closed) and cap.position.is_equal_approx(cap_closed), "Instant closing seats both top parts exactly")
	prop.call("set_open", true, true)
	await get_tree().create_timer(0.3).timeout
	check(bool(prop.get("is_open")) and not strainer.position.is_equal_approx(strainer_closed) and not cap.position.is_equal_approx(cap_closed), "Animated opening finishes with both top parts removed")
	prop.call("set_open", false, true)
	await get_tree().create_timer(0.3).timeout
	check(not bool(prop.get("is_open")) and strainer.position.is_equal_approx(strainer_closed) and cap.position.is_equal_approx(cap_closed), "Animated closing returns both top parts to their seats")
	prop.call("animate_shake")
	await get_tree().create_timer(0.04).timeout
	check(not is_equal_approx(prop.rotation, rotation_before), "Closed shaker begins moving during shake")
	await get_tree().create_timer(0.75).timeout
	check(is_equal_approx(prop.rotation, rotation_before), "Shake animation restores original rotation")
