extends Node
## Uses five explicitly isolated saves and real Supplies transactions.
const OUTPUT := "res://../output/backpack-preview"
const GIN := "sku_gin_london_dry"
const TONIC := "sku_tonic_water"
const LIME := "sku_lime_wedge"
var home: Control
var bag: Control
var checks := 0
var failures: Array[String] = []
var screenshots := false
var watchdog: Timer

func _ready() -> void:
	for prefix: String in ["--game-save=", "--dialogue-save=", "--slot-wallet=", "--menu-save=", "--supplies-save="]:
		var isolated := false
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with(prefix):
				isolated = temporary(argument.trim_prefix(prefix))
		if not isolated:
			push_error("Backpack test requires all five explicit /tmp saves: " + prefix)
			get_tree().quit(2)
			return
	for service_name: String in ["GameSession", "StoryDialogue", "SlotWallet", "MenuCatalog", "Supplies"]:
		var service := get_node_or_null("/root/" + service_name)
		if service == null or not temporary(str(service.get("save_path"))):
			push_error("Refusing backpack test against player save: " + service_name)
			get_tree().quit(2)
			return
	TimeManager.set_process(false)
	GameSession.set_process(false)
	screenshots = "--screenshots" in OS.get_cmdline_user_args()
	watchdog = Timer.new()
	watchdog.one_shot = true
	watchdog.wait_time = 45
	watchdog.timeout.connect(func(): push_error("Backpack test timed out"); get_tree().quit(2))
	add_child(watchdog)
	watchdog.start()
	call_deferred("run")

func temporary(path: String) -> bool:
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

func click_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	get_viewport().push_input(event, true)
	await get_tree().process_frame
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	get_viewport().push_input(release, true)
	await settle()

func click(control: Control) -> void:
	check(is_instance_valid(control), "Required native click target exists")
	if is_instance_valid(control):
		await click_at(control.get_global_rect().get_center())

func control(name: String) -> Control:
	return bag.find_child(name, true, false) as Control if is_instance_valid(bag) else null

func ids() -> Array[String]:
	var result: Array[String] = []
	for button: Button in bag.get("item_buttons"):
		result.append(str(button.get_meta("item_id", "")))
	return result

func detail_text() -> String:
	var result := ""
	var details := control("ItemDetails")
	if details != null:
		for label: Label in details.find_children("*", "Label", true, false):
			if label.is_visible_in_tree():
				result += label.text + "\n"
	return result

func open_bag() -> bool:
	await click(home.find_child("BackpackButton", true, false) as Control)
	await get_tree().create_timer(0.22).timeout
	check(Navigation.current_route == &"backpack" and is_instance_valid(home.active_page), "Native backpack icon opens inventory")
	bag = home.active_page
	return Navigation.current_route == &"backpack" and is_instance_valid(bag)

func capture(name: String) -> void:
	if not screenshots or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(folder)
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png")) == OK, "Saved screenshot: " + name)

func verify_layout() -> void:
	var original := home.size
	for dimensions: Vector2 in [Vector2(1600, 900), Vector2(1024, 768), Vector2(960, 540)]:
		home.size = dimensions
		home.call("_fit_layout")
		var slot := home.find_child("SlotsButton", true, false) as Control
		var icon := home.find_child("BackpackButton", true, false) as Control
		var clock := home.find_child("TimeValue", true, false) as Control
		check(not slot.get_global_rect().intersects(icon.get_global_rect()), "Slot and bag icons remain separate: " + str(dimensions))
		check(not clock.get_global_rect().intersects(slot.get_global_rect()), "Clock does not overlap icons: " + str(dimensions))
		var stage := home.get_node("%Stage") as Control
		var extent := stage.position + stage.size * stage.scale
		check(stage.position.x >= -0.1 and stage.position.y >= -0.1 and extent.x <= dimensions.x + 0.1 and extent.y <= dimensions.y + 0.1, "Home fits inventory entry at " + str(dimensions))
	home.size = original
	home.call("_fit_layout")

func run() -> void:
	TimeManager.restore({"day": 2, "minutes": 21 * 60, "elapsed": 0.2})
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	verify_layout()
	await capture("01-home-backpack-icon")
	var inventory_before := Supplies.serialize()
	var wallet_before := SlotWallet.balance
	var story_before := StoryDialogue.session_snapshot()
	var guest_before: Dictionary = home.get("guest_profile").duplicate(true)
	var count_before := int(home.get("guest_count"))
	if not await open_bag():
		await finish()
		return
	check(TimeManager.running, "Opening backpack leaves the running clock unchanged")
	check(home.get_node("%GuestLayer").visible, "Guest remains visible behind the inventory")
	check(Supplies.serialize() == inventory_before and SlotWallet.balance == wallet_before, "Browsing inventory changes neither stock nor coins")
	check((bag.get("products") as Array).size() == 10, "Fresh inventory contains default ten tools and glasses only")
	for id: String in ids():
		check(Supplies.get_item(id).storage_mode == "permanent" and Supplies.is_owned(id), "Inventory grid initially shows genuinely owned reusable items: " + id)
	check(detail_text().contains("已拥有"), "Permanent item detail shows ownership")
	await capture("02-default-equipment")
	var before_time := TimeManager.visual_minutes()
	TimeManager._process(0.6)
	await settle()
	check(TimeManager.visual_minutes() > before_time and TimeManager.running, "Clock progresses while backpack stays open")
	await click(control("Category_原酒"))
	check((bag.get("products") as Array).is_empty() and ids().is_empty(), "Locked and zero-stock liquor is absent")
	check((control("NextPage") as Button).disabled and (control("PreviousPage") as Button).disabled, "Empty category disables paging")
	await capture("03-empty-liquor-category")
	check(Supplies.purchase(GIN, 2), "Real transaction buys two gin bottles")
	await settle()
	check(ids() == [GIN] and str(bag.get("selected_id")) == GIN, "Live purchase populates an open empty category")
	check(Supplies.consume(GIN, 650), "Real consumption leaves 100 ml in the current bottle")
	await settle()
	var detail := detail_text()
	check(detail.contains("100 ml") and detail.contains("850 ml"), "Bag shows current 100 ml and total 850 ml after consumption")
	check(detail.contains("2") and detail.contains("瓶"), "Container count includes the currently open bottle")
	await capture("04-open-bottle-details")
	check(Supplies.purchase(TONIC, 1) and Supplies.purchase(LIME, 1), "Real purchases add mixer and garnish")
	await settle()
	await click(control("Category_装饰品"))
	check(ids() == [LIME], "Garnish appears in its own category")
	var quantity_before := int(Supplies.get_state(LIME).quantity)
	check(Supplies.consume(LIME, 1), "Count-only garnish consumption succeeds")
	await settle()
	check(detail_text().contains(str(quantity_before - 1)) and not detail_text().contains("ml"), "Garnish shows actual remaining pieces without bottle units")
	await click(control("Category_全部"))
	check((bag.get("products") as Array).size() == 13, "All category combines three consumables and ten reusable items")
	await click(control("Product_" + TONIC))
	check(str(bag.get("selected_id")) == TONIC and detail_text().contains("汤力水"), "Native item click selects its own details")
	await click(control("Product_" + GIN))
	check(str(bag.get("selected_id")) == GIN and detail_text().contains("850 ml"), "Selecting another item restores its actual quantities")
	await capture("05-filled-backpack")
	await click(control("NextPage"))
	await click(control("NextPage"))
	check(int(bag.get("page_index")) == 2 and (control("NextPage") as Button).disabled, "Thirteen items expose a bounded third page")
	var selected_last := str(bag.get("selected_id"))
	check(Supplies.consume(GIN, 850), "Consume remaining gin across both bottles")
	await settle()
	check(Supplies.is_unlocked(GIN) and Supplies.total_remaining(GIN) == 0, "Empty gin retains discovery but has no physical stock")
	check(int(bag.get("page_index")) == 1 and (bag.get("products") as Array).size() == 12, "Removing an item clamps the old third page into the second")
	check(str(bag.get("selected_id")) == selected_last and not ids().has(GIN), "Selection survives unrelated consumption and empty gin disappears")
	await click(control("Category_原酒"))
	check(ids().is_empty(), "Unlocked but exhausted liquor does not remain in the backpack")
	await click(control("Category_器材"))
	check((bag.get("products") as Array).size() == 6 and detail_text().contains("已拥有"), "Equipment category contains six owned tools")
	await click(control("Category_杯型"))
	check((bag.get("products") as Array).size() == 4, "Glassware category contains four owned glasses")
	var final_stock := Supplies.serialize()
	await click(control("CloseButton"))
	check(Navigation.current_route == &"home", "Native close returns to the same reception")
	check(StoryDialogue.session_snapshot() == story_before and home.get("guest_profile") == guest_before and int(home.get("guest_count")) == count_before, "Backpack does not reset guest or story progress")
	if await open_bag():
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = true
		get_viewport().push_input(key, true)
		await settle()
		check(Navigation.current_route == &"home", "Escape dismisses inventory")
	if await open_bag():
		await click_at((home.find_child("ShopButton", true, false) as Control).get_global_rect().get_center())
		check(Navigation.current_route == &"home", "Outside click closes the modal without entering an underlying menu")
	check(Supplies.serialize() == final_stock, "Reopening and dismissing does not change persisted inventory")
	check(TimeManager.running, "Dismissal keeps the clock running")
	await finish()

func finish() -> void:
	watchdog.stop()
	if is_instance_valid(home):
		home.queue_free()
		await settle()
	home = null
	bag = null
	print("BACKPACK VERIFICATION: ", "PASS" if failures.is_empty() else "FAIL", " — ", checks, " checks; native entry, categories, real stock, package amounts, live refresh, pagination, modal close, time, guest continuity")
	get_tree().quit(0 if failures.is_empty() else 1)
