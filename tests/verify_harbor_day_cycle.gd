extends Node
## Run with all five explicit /tmp saves; --screenshots captures the real shop.
## Exercise the clock-to-scene chain and native input, without replacing services.

const OUTPUT := "res://../output/harbor-time-preview"
const ART := "res://assets/art/shop/harbor-shop-"
const UNIFORMS := ["day_weight", "night_weight", "dawn_weight"]
var failures: Array[String] = []
var checks := 0
var screenshots := false
var home: Control
var shop: Control
var harbor: TextureRect
var saloon: TextureRect
var counter: TextureRect
var scene_geometry: Dictionary = {}
var watchdog: Timer

func _ready() -> void:
	# Check both the arguments and their resolved service paths before instantiating home.
	for prefix: String in ["--game-save=", "--dialogue-save=", "--slot-wallet=", "--menu-save=", "--supplies-save="]:
		var isolated := false
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with(prefix):
				isolated = _temporary(argument.trim_prefix(prefix))
		if not isolated:
			push_error("Provide all five explicit temporary save arguments, including " + prefix)
			get_tree().quit(2)
			return
	for service_name: String in ["GameSession", "StoryDialogue", "SlotWallet", "MenuCatalog", "Supplies"]:
		var service := get_node_or_null("/root/" + service_name)
		if service == null or not _temporary(str(service.get("save_path"))):
			push_error("Refusing harbor lighting test against a real or missing save service: " + service_name)
			get_tree().quit(2)
			return
	screenshots = "--screenshots" in OS.get_cmdline_user_args()
	TimeManager.set_process(false)
	GameSession.set_process(false)
	watchdog = Timer.new()
	watchdog.one_shot = true
	watchdog.wait_time = 45.0
	add_child(watchdog)
	watchdog.timeout.connect(func(): push_error("Harbor lighting test timeout"); get_tree().quit(2))
	watchdog.start()
	call_deferred("run")

func _temporary(path: String) -> bool:
	var clean := path.simplify_path()
	return clean.begins_with("/tmp/") or clean.begins_with("/private/tmp/")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

func set_clock(minute: float) -> void:
	var normalized := fposmod(minute, 1440.0)
	TimeManager.restore({"day": 2, "minutes": int(floor(normalized)), "elapsed": normalized - floor(normalized)})
	TimeManager.time_changed.emit(TimeManager.day, TimeManager.minutes_since_midnight)

func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = point
	down.global_position = point
	down.pressed = true
	get_viewport().push_input(down, true)
	await get_tree().process_frame
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	get_viewport().push_input(up, true)
	await settle()

func click(control: Control) -> void:
	if not is_instance_valid(control):
		check(false, "Required native click target exists")
		return
	await click_at(control.get_global_rect().get_center())

func open_harbor() -> bool:
	await click(home.find_child("ShopButton", true, false) as Control)
	await get_tree().create_timer(0.22).timeout
	check(Navigation.current_route == &"shop" and is_instance_valid(home.active_page), "Native home shop entry opens harbor")
	if Navigation.current_route != &"shop" or not is_instance_valid(home.active_page):
		return false
	shop = home.active_page
	harbor = shop.find_child("HarborBackground", true, false) as TextureRect
	counter = shop.find_child("CounterForeground", true, false) as TextureRect
	check(harbor != null and harbor.has_method("weights_at"), "Harbor exposes its clock-controlled background")
	check(counter != null, "Counter foreground exists")
	return harbor != null and counter != null and harbor.has_method("weights_at")

func capture(name: String) -> void:
	if not screenshots or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(folder)
	var frame := get_viewport().get_texture().get_image()
	check(frame != null and frame.save_png(folder.path_join(name + ".png")) == OK, "GUI screenshot saved: " + name)

func weights_match_clock(label: String) -> void:
	var expected: Vector3 = saloon.call("weights_at", TimeManager.visual_minutes())
	var actual: Vector3 = harbor.get("light_weights")
	check(actual.is_equal_approx(expected), label + ": harbor and saloon weights agree with fractional clock")
	check((saloon.get("light_weights") as Vector3).is_equal_approx(expected), label + ": saloon applies the same live time")
	var blend := harbor.material as ShaderMaterial
	if blend == null:
		check(false, label + ": real shader material exists")
		return
	for index in range(UNIFORMS.size()):
		check(is_equal_approx(float(blend.get_shader_parameter(UNIFORMS[index])), expected[index]), label + ": shader receives " + UNIFORMS[index])
	check(counter.material == harbor.material, label + ": foreground shares the current background weights")

func verify_assets_and_counter() -> void:
	var blend := harbor.material as ShaderMaterial
	check(blend != null, "Harbor uses a material that blends actual paintings")
	if blend == null:
		return
	var textures := {"day": blend.get_shader_parameter("day_texture"), "dusk": harbor.texture,
		"night": blend.get_shader_parameter("night_texture"), "dawn": blend.get_shader_parameter("dawn_texture")}
	var paths: Array[String] = []
	for phase: String in textures:
		var texture := textures[phase] as Texture2D
		check(texture != null, "Real " + phase + " painting is loaded")
		if texture == null:
			continue
		check(texture.resource_path == ART + phase + ".png", "The " + phase + " sampler uses its own harbor painting")
		var aspect := float(texture.get_width()) / maxf(texture.get_height(), 1)
		check(absf(aspect - 1600.0 / 900.0) < 0.004, "The " + phase + " painting fits the shared 16:9 scene geometry")
		check(not paths.has(texture.resource_path), "The " + phase + " painting has a distinct asset")
		paths.append(texture.resource_path)
	check(counter.texture == harbor.texture and not counter.texture is AtlasTexture, "Counter samples the same full painting as the background")
	check(counter.material == harbor.material, "Background and counter share one blend material")
	var clip := counter.get_parent() as Control
	check(clip != null and clip.name == "CounterClip" and clip.clip_contents, "Counter is cropped by a clipping control")
	if clip != null:
		check(clip.position.is_equal_approx(Vector2(0, 742)) and clip.size.is_equal_approx(Vector2(703, 158)), "Counter clip matches the painted foreground bounds")
		check(counter.position.is_equal_approx(Vector2(0, -742)) and counter.size.is_equal_approx(harbor.size), "Counter retains full-frame UV coordinates inside the clip")
		check(counter.get_global_rect().is_equal_approx(harbor.get_global_rect()), "Full foreground sampling aligns with the background globally")
	check(harbor.mouse_filter == Control.MOUSE_FILTER_IGNORE and counter.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Environment paintings leave native input accessible")
	for name: String in ["HarborBackground", "Merchant", "ShelfProducts", "CounterClip", "CounterForeground"]:
		var control := shop.find_child(name, true, false) as Control
		if control != null:
			scene_geometry[name] = {"position": control.position, "size": control.size, "scale": control.scale}

func verify_transition_boundaries() -> void:
	# Compare only transition endpoints and mixed midpoints. This checks continuity
	# and compatibility without repeating the whole minute-by-minute implementation.
	for boundary: float in [0.0, 240.0, 330.0, 390.0, 480.0, 960.0, 1080.0, 1140.0, 1260.0, 1440.0]:
		var before: Vector3 = harbor.call("weights_at", boundary - 0.05)
		var after: Vector3 = harbor.call("weights_at", boundary + 0.05)
		check(before.distance_to(after) < 0.003, "Lighting is continuous across minute " + str(boundary))
		for minute: float in [boundary - 0.05, boundary, boundary + 0.05]:
			var actual: Vector3 = harbor.call("weights_at", minute)
			check(actual.is_equal_approx(saloon.call("weights_at", minute)), "Harbor and saloon schedules agree near " + str(minute))
			check(actual.x >= 0 and actual.y >= 0 and actual.z >= 0 and actual.x + actual.y + actual.z <= 1.0001, "Blend weights remain valid near " + str(minute))
	for minute: float in [285.0, 435.0, 1020.0, 1200.0]:
		var weights: Vector3 = harbor.call("weights_at", minute)
		check(weights.is_equal_approx(saloon.call("weights_at", minute)), "Mixed phase shares the saloon schedule at " + str(minute))
		var active := int(weights.x > 0) + int(weights.y > 0) + int(weights.z > 0) + int(1.0 - weights.x - weights.y - weights.z > 0.0001)
		check(active == 2, "Transition uses exactly two paintings at " + str(minute))

func verify_scene_tint(label: String) -> void:
	var ambient: Color = harbor.get("ambient_tint")
	var merchant := shop.find_child("Merchant", true, false) as TextureRect
	check(merchant != null and merchant.self_modulate.is_equal_approx(ambient), label + ": merchant receives ambient lighting")
	var receipt_icon: TextureRect = shop.get("receipt_icon")
	check(receipt_icon != null and receipt_icon.self_modulate.is_equal_approx(ambient), label + ": selected goods receive ambient lighting")
	for product: Button in shop.get("slot_buttons"):
		var art: TextureRect = product.get("art")
		check(art != null and art.self_modulate.is_equal_approx(ambient), label + ": shelf art receives ambient lighting")
	# Validate inherited modulation as well: a tinted parent would also dim paper/text.
	var untinted := true
	var paper_count := 0
	for node in shop.find_children("*", "Control", true, false):
		var is_paper := false
		for property: Dictionary in node.get_property_list():
			if property.name == "hanging":
				is_paper = true
				paper_count += 1
				break
		if not node is Label and not is_paper:
			continue
		var ancestor: Node = node
		while ancestor != null:
			if ancestor is CanvasItem:
				var canvas_item := ancestor as CanvasItem
				if not canvas_item.modulate.is_equal_approx(Color.WHITE) or not canvas_item.self_modulate.is_equal_approx(Color.WHITE):
					untinted = false
			if ancestor == shop:
				break
			ancestor = ancestor.get_parent()
	check(paper_count > 6 and untinted, label + ": paper and writing remain free of environment tint")
	for name: String in scene_geometry:
		var control := shop.find_child(name, true, false) as Control
		var original: Dictionary = scene_geometry[name]
		check(control != null and control.position.is_equal_approx(original.position) and control.size.is_equal_approx(original.size) and control.scale.is_equal_approx(original.scale), label + ": lighting preserves geometry for " + name)

func verify_fractional_clock() -> void:
	set_clock(19 * 60 + 30.2)
	await settle()
	var before: Vector3 = harbor.get("light_weights")
	TimeManager._process(0.6)
	await settle()
	weights_match_clock("Between clock ticks")
	check(TimeManager.minutes_since_midnight == 1170 and is_equal_approx(TimeManager.visual_minutes(), 1170.8), "Clock retains the fractional visual minute")
	check((harbor.get("light_weights") as Vector3).distance_to(before) > 0.00001, "Lighting advances before the next integer clock tick")
	set_clock(18 * 60)
	check(TimeManager.start_early(), "Temporary clock can begin early-opening fast-forward")
	TimeManager._process(2.35)
	await settle()
	weights_match_clock("Fast-forward")
	var minute := TimeManager.visual_minutes()
	check(TimeManager.fast_forwarding and minute > 19 * 60 and minute < 20 * 60, "Fast-forward reaches the blended sunset interval")
	check(absf(minute - round(minute)) > 0.001, "Accelerated visual time includes fractional progress")

func verify_pause_and_rollovers() -> void:
	set_clock(19 * 60 + 30.25)
	await settle()
	var frozen_time := TimeManager.visual_minutes()
	var frozen_weights: Vector3 = harbor.get("light_weights")
	TimeManager.set_running(false)
	TimeManager._process(0.7)
	await settle()
	check(is_equal_approx(TimeManager.visual_minutes(), frozen_time) and (harbor.get("light_weights") as Vector3).is_equal_approx(frozen_weights), "Paused clock also freezes harbor lighting between ticks")
	weights_match_clock("Paused clock")
	TimeManager.set_running(true)
	set_clock(23 * 60 + 59.5)
	await settle()
	var before_midnight: Vector3 = harbor.get("light_weights")
	TimeManager._process(0.75)
	await settle()
	check(TimeManager.minutes_since_midnight == 0 and TimeManager.day == 2, "Real clock update crosses midnight within the same business day")
	check((harbor.get("light_weights") as Vector3).is_equal_approx(before_midnight), "Midnight preserves the continuous night painting")
	weights_match_clock("Midnight rollover")
	set_clock(3 * 60 + 59)
	TimeManager.advance_minutes(1)
	await settle()
	check(TimeManager.minutes_since_midnight == 240 and TimeManager.day == 3 and not TimeManager.is_open, "Actual minute advance closes business at 04:00 while harbor is open")
	check(Navigation.current_route == &"shop" and home.active_page == shop, "04:00 leaves harbor browsing available")
	weights_match_clock("04:00 close boundary")
	TimeManager._process(0.5)
	await settle()
	weights_match_clock("After 04:00 close")
	check((harbor.get("light_weights") as Vector3).z > 0, "Fractional clock begins dawn gradually after closing")

func verify_merchant_click() -> void:
	var target := shop.find_child("MerchantInteraction", true, false) as Button
	check(target != null and not target.disabled, "Merchant remains an enabled native button at night")
	if target == null:
		return
	var point := Vector2.ZERO
	var found := false
	for y: float in [340.0, 300.0, 380.0, 260.0]:
		for x: float in [320.0, 280.0, 360.0, 240.0, 400.0]:
			var candidate := Vector2(x, y)
			if target.call("_has_point", candidate):
				point = target.get_global_transform() * candidate
				found = true
				break
		if found:
			break
	check(found, "Visible merchant silhouette supplies a native click point")
	if found:
		var line_before := str(shop.get("merchant_line_index"))
		await click_at(point)
		check(str(shop.get("merchant_line_index")) != line_before, "Native mouse click still changes merchant dialogue at night")

func run() -> void:
	set_clock(12 * 60 + 0.4)
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	saloon = home.get_node("Background") as TextureRect
	if not await open_harbor():
		await finish()
		return
	weights_match_clock("First entry at noon")
	verify_assets_and_counter()
	verify_transition_boundaries()
	var day_tint: Color = harbor.get("ambient_tint")
	for phase: Dictionary in [
		{"minute": 720.0, "weights": Vector3(1, 0, 0), "name": "01-day-1200"},
		{"minute": 1110.0, "weights": Vector3.ZERO, "name": "02-dusk-1830"},
		{"minute": 1350.0, "weights": Vector3(0, 1, 0), "name": "03-night-2230"},
		{"minute": 360.0, "weights": Vector3(0, 0, 1), "name": "04-dawn-0600"},
		{"minute": 1185.0, "name": "05-dusk-to-night-1945"},
		{"minute": 285.0, "name": "06-night-to-dawn-0445"},
	]:
		set_clock(float(phase.minute))
		await settle()
		weights_match_clock(str(phase.name))
		if phase.has("weights"):
			check((harbor.get("light_weights") as Vector3).is_equal_approx(phase.weights), str(phase.name) + ": independent painting is fully active")
		verify_scene_tint(str(phase.name))
		await capture(str(phase.name))
	await verify_fractional_clock()
	await verify_pause_and_rollovers()
	set_clock(22 * 60)
	await settle()
	check(not (harbor.get("ambient_tint") as Color).is_equal_approx(day_tint), "Night visibly changes scene object lighting")
	await click(shop.find_child("Category_配料", true, false) as Control)
	verify_scene_tint("Products created after a night-time category change")
	await verify_merchant_click()
	var old_shop_id := shop.get_instance_id()
	await click(shop.find_child("BackButton", true, false) as Control)
	check(Navigation.current_route == &"home", "Native back control returns to saloon")
	set_clock(6 * 60 + 0.35)
	await settle()
	if await open_harbor():
		check(shop.get_instance_id() != old_shop_id, "Reentry creates a fresh shop scene")
		weights_match_clock("Reentry at dawn")
		check((harbor.get("light_weights") as Vector3).is_equal_approx(Vector3(0, 0, 1)), "Reentry immediately paints the current dawn phase")
		verify_scene_tint("Reentry at dawn")
		await capture("07-reentry-dawn")
	await finish()

func finish() -> void:
	watchdog.stop()
	if is_instance_valid(home):
		home.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	home = null
	shop = null
	harbor = null
	saloon = null
	counter = null
	print("HARBOR DAY CYCLE VERIFICATION: ", "PASS" if failures.is_empty() else "FAIL", " — ", checks, " checks; distinct paintings, saloon schedule, fractional clock, counter UV alignment, object lighting, clear paper, native merchant input, reentry")
	get_tree().quit(0 if failures.is_empty() else 1)
