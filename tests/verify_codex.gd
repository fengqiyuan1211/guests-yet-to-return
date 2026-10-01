extends Node
var failures: Array[String] = []
var home: Control
var capture := false

func _ready() -> void:
	for service_name: String in ["SlotWallet", "StoryDialogue", "GameSession", "MenuCatalog", "Supplies"]:
		var service := get_node_or_null("/root/" + service_name)
		var path := str(service.get("save_path")) if service != null else ""
		if not path.begins_with("/tmp/") and not path.begins_with("/private/tmp/"):
			push_error("Refusing a test against live saves: " + service_name)
			get_tree().quit(2)
			return
	capture = "--screenshots" in OS.get_cmdline_user_args()
	get_tree().create_timer(45).timeout.connect(func(): push_error("Codex test timed out"); get_tree().quit(2))
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	if not ok:
		failures.append(description)
		push_error(description)

func settle(seconds := 0.1) -> void:
	await get_tree().create_timer(seconds).timeout

func click(button: Control) -> void:
	click_at(button.get_global_rect().get_center())

func click_at(point: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = point
	down.pressed = true
	get_viewport().push_input(down, true)
	var up := down.duplicate()
	up.pressed = false
	get_viewport().push_input(up, true)

func hover(button: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	motion.global_position = motion.position
	get_viewport().push_input(motion, true)

func missing_tooltip(recipe_id: String) -> String:
	var names: Array[String] = []
	for item: Dictionary in Supplies.missing_recipe_requirements(recipe_id).ingredients:
		if not names.has(str(item.name)):
			names.append(str(item.name))
	return "缺少：\n" + "\n".join(names)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	get_viewport().push_input(event, true)

func screenshot(filename: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../output/codex-classics-preview")
	DirAccess.make_dir_recursive_absolute(path)
	check(get_viewport().get_texture().get_image().save_png(path.path_join(filename)) == OK, "Screenshot saved")

func run() -> void:
	check(MenuCatalog.reset_game() and Supplies.reset_game(), "Private fixture starts with no materials or unlocked drinks")
	SlotWallet.balance = 10000
	check(SlotWallet.persist(), "Private fixture funds are saved only to the isolated wallet")
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle(0.5)
	var balance := SlotWallet.balance
	check(home.find_child("QuickAccess", true, false) == null, "Duplicate bottom shortcuts removed")
	check(home.find_child("StockNote", true, false) == null, "Duplicate shop card removed")
	check(home.find_child("GuestNote", true, false).size.y < 400, "Right guest note stays compact")
	await screenshot("01-home-open-space.png")
	click(home.get_node("%OpenButton"))
	await settle(4.2)
	home.get_node("%GuestLayer").show_guest(1)
	await settle(0.5)
	var guest_id: String = home.guest_profile.id
	await screenshot("02-home-guest.png")
	click(home.find_child("CodexButton", true, false))
	await settle(0.4)
	var journal = home.active_page
	check(Navigation.current_route == &"codex", "Native sidebar opens journal")
	check(home.get_node("%HomeContent").visible, "Shared top and sidebar stay visible")
	check(not home.find_child("GuestDialogue", true, false).visible, "Dialogue hidden on codex")
	check(journal.page_content.find_children("CardSlot*", "Button", true, false).size() == 6, "Six individual cocktail card positions")
	check(journal.page_content.get_child(0).size == journal.PAGE_SIZE, "Paper texture respects journal bounds")
	check(journal.previous_button.disabled and not journal.next_button.disabled, "First page bounds")
	var tutorial: Button = journal.page_content.find_child("CardSlot1", true, false)
	check(tutorial != null and tutorial.disabled and not tutorial.get_meta("has_recipe", false), "First position remains blank and disabled for the tutorial")
	if tutorial != null:
		click(tutorial)
	check(not journal.turning and journal.page_index == 0 and journal.detail_id.is_empty(), "Clicking the tutorial placeholder does not open a drink or turn the page")
	var cocktail_ids := ["last_word", "mojito", "gin_and_tonic", "long_island_iced_tea", "manhattan"]
	check(not journal.allow_locked_details, "Production configuration forbids locked drink previews")
	for index in range(cocktail_ids.size()):
		var recipe_id: String = cocktail_ids[index]
		var locked_slot: Button = journal.page_content.find_child("CardSlot%d" % (index + 2), true, false)
		check(locked_slot != null and locked_slot.disabled and locked_slot.is_locked, "Undiscovered drink is disabled: " + recipe_id)
		check(not MenuCatalog.get_recipe(recipe_id).unlocked, "Fixture drink starts undiscovered: " + recipe_id)
		if locked_slot == null:
			continue
		var expected_tooltip := missing_tooltip(recipe_id)
		check(locked_slot.tooltip_text == expected_tooltip, "Locked hint contains only actual missing item names: " + recipe_id)
		check(locked_slot.mouse_default_cursor_shape == Control.CURSOR_ARROW, "Locked drink uses an arrow cursor: " + recipe_id)
		hover(locked_slot)
		await settle(0.02)
		check(get_viewport().gui_get_hovered_control() == locked_slot and locked_slot.get_tooltip(locked_slot.size / 2) == expected_tooltip, "Native hover resolves the missing-only hint: " + recipe_id)
		click(locked_slot)
		await settle(0.02)
		check(journal.detail_id.is_empty(), "Native click cannot open an undiscovered drink: " + recipe_id)
		journal.show_detail(recipe_id)
		check(journal.detail_id.is_empty(), "Direct detail entry also respects the lock: " + recipe_id)
	click(journal.tabs[2])
	await settle(0.1)
	var filtered_slot: Button = journal.page_content.find_child("CardSlot2", true, false)
	check(filtered_slot != null and filtered_slot.disabled, "Undiscovered filter keeps recipe cards disabled")
	if filtered_slot != null:
		click(filtered_slot)
	check(journal.selected_filter == 2 and journal.page_index == 0 and journal.detail_id.is_empty(), "Clicking a locked filtered card preserves filter and page")
	click(journal.tabs[0])
	# Exercise the real discovery path; no preview flag or direct unlock manipulation.
	for recipe_id: String in cocktail_ids:
		for ingredient: Dictionary in MenuCatalog.get_recipe(recipe_id).ingredients:
			if not ingredient.get("required", true) or MenuCatalog._is_ice(ingredient):
				continue
			var sku_id: String = str(ingredient.get("sku_id", ""))
			if not Supplies.is_unlocked(sku_id):
				check(Supplies.purchase(sku_id), "Fixture purchases required material: " + sku_id)
		check(MenuCatalog.get_recipe(recipe_id).unlocked, "Required purchases permanently discover the drink: " + recipe_id)
	await settle(0.1)
	balance = SlotWallet.balance
	for index in range(cocktail_ids.size()):
		var expected_id: String = cocktail_ids[index]
		var slot: Button = journal.page_content.find_child("CardSlot%d" % (index + 2), true, false)
		check(slot != null and slot.get_meta("has_recipe", false) and slot.get_meta("cocktail_id", "") == expected_id, "Each card position holds one distinct cocktail: " + expected_id)
		if slot == null:
			continue
		check(not slot.disabled and MenuCatalog.get_recipe(expected_id).unlocked, "Purchased drink is enabled for viewing: " + expected_id)
		check(slot.tooltip_text == "查看酒谱", "Discovered drink has its ordinary viewing hint: " + expected_id)
		click(slot)
		await settle(0.12)
		check(journal.detail_id == expected_id, "Actual card click opens matching details: " + expected_id)
		if journal.detail_id != expected_id:
			continue
		var title: Label = journal.page_content.find_child("RecipeTitle", true, false)
		var ingredients: Control = journal.page_content.find_child("Ingredients", true, false)
		var flavors: Control = journal.page_content.find_child("FlavorTags", true, false)
		var recipe: Dictionary = MenuCatalog.get_recipe(expected_id)
		check(title != null and title.text.contains(recipe.name), "Detail shows the selected drink name: " + expected_id)
		check(ingredients != null and ingredients.get_child_count() == recipe.ingredients.size(), "Detail recipe includes all non-ice ingredients: " + expected_id)
		check(flavors != null and flavors.get_child_count() == recipe.flavor_tags.size(), "Detail shows exactly the flavor tags: " + expected_id)
		if flavors != null:
			for tag in flavors.get_children():
				check(tag is Label and recipe.flavor_tags.has(tag.text), "Flavor tags use text only")
		await screenshot("11-detail-%s.png" % expected_id)
		var back: Button = journal.page_content.find_child("BackToCodex", true, false)
		check(back != null, "Detail has a return control")
		if back != null:
			click(back)
		await settle(0.12)
		check(journal.detail_id.is_empty() and journal.selected_filter == 0 and journal.page_index == 0, "Returning preserves current filter and page")
	click(journal.tabs[0])
	click(journal.tabs[1])
	check(journal.selected_filter == 1 and not journal.turning, "Ink filter remains independent of page turning")
	click(journal.tabs[0])
	await screenshot("03-codex-page-1.png")
	# Click blank paper far from the small arrow, exercising the full gutter hit area.
	click_at(journal.get_global_transform_with_canvas() * (journal.PAGE_ORIGIN + Vector2(1225, 194)))
	await settle(0.22)
	check(journal.turning and journal.curl.visible, "Turning leaf is visible during animation")
	var progress: float = journal.curl.material.get_shader_parameter("progress")
	check(progress > 0.0 and progress < 1.0, "Curl shader progresses")
	await screenshot("04-turn-early.png")
	journal.turn_page(1)
	journal.turn_page(-1)
	await settle(0.18)
	await screenshot("05-turn-middle.png")
	await settle(0.23)
	await screenshot("06-turn-late.png")
	await settle(0.55)
	check(journal.page_index == 1 and not journal.turning, "Repeated input only advances one page")
	await screenshot("07-codex-page-2.png")
	key(KEY_RIGHT)
	await settle(1.1)
	check(journal.page_index == 2 and journal.next_button.disabled, "Keyboard and last page bounds")
	journal.turn_page(1)
	check(not journal.turning, "No turn beyond last leaf")
	click_at(journal.get_global_transform_with_canvas() * (journal.PAGE_ORIGIN + Vector2(65, 556)))
	await settle(0.4)
	await screenshot("08-turn-back.png")
	await settle(0.7)
	check(journal.page_index == 1, "Previous page settles correctly")
	# Swipe uses actual mouse input, the same path as emulated touch.
	var origin: Vector2 = journal.get_global_transform_with_canvas() * Vector2(900, 500)
	var destination: Vector2 = journal.get_global_transform_with_canvas() * Vector2(1080, 500)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = origin
	down.pressed = true
	get_viewport().push_input(down, true)
	var up := down.duplicate()
	up.position = destination
	up.pressed = false
	get_viewport().push_input(up, true)
	await settle(1.1)
	check(journal.page_index == 0, "Swipe returns to previous page")
	click(journal.tabs[2])
	check(journal.selected_filter == 2, "Locked filter remains selectable")
	click(home.find_child("ShopButton", true, false))
	await settle(0.2)
	check(Navigation.current_route == &"shop", "Sidebar remains interactive from journal")
	key(KEY_ESCAPE)
	await settle(0.2)
	check(home.guest_profile.id == guest_id and home.get_node("%GuestLayer").visible, "Guest survives route round trip")
	check(home.find_child("GuestDialogue", true, false).visible, "Dialogue restored")
	check(not home.get_node("%ActionCaption").visible, "Service visibility restored")
	click(home.find_child("CodexButton", true, false))
	await settle(0.3)
	journal = home.active_page
	click(journal.next_button)
	await settle(0.15)
	key(KEY_ESCAPE)
	await settle(1.0)
	check(Navigation.current_route == &"home", "Can leave during animation")
	# Render real aspect ratios, checking fit and native navigation at each size.
	for dimensions in [Vector2i(1280, 576), Vector2i(1024, 768)]:
		get_window().size = dimensions
		await settle(0.3)
		await screenshot("09-home-%dx%d.png" % [dimensions.x, dimensions.y])
		click(home.find_child("CodexButton", true, false))
		await settle(0.3)
		check(Navigation.current_route == &"codex", "Responsive sidebar hit test")
		await screenshot("10-codex-%dx%d.png" % [dimensions.x, dimensions.y])
		key(KEY_ESCAPE)
		await settle(0.15)
	check(SlotWallet.balance == balance, "UI browsing does not modify wallet")
	print("CODEX VERIFICATION: ", "PASS" if failures.is_empty() else "FAIL", " — reserved tutorial, five cocktail details, lock gate, curl, reverse, bounds, rapid clicks, swipe, sidebar, guest persistence, responsive layout")
	get_tree().quit(0 if failures.is_empty() else 1)
