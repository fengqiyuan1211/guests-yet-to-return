extends Node
## Isolated native lock, hover and permanent-unlock verification.

const RECIPE := "gin_and_tonic"
const MATERIALS := ["sku_gin_london_dry", "sku_tonic_water", "sku_lime_wedge"]
var journal: Control
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	for name_value: String in ["SlotWallet", "StoryDialogue", "GameSession", "MenuCatalog", "Supplies"]:
		var service := get_node_or_null("/root/" + name_value)
		var path := str(service.get("save_path")) if service != null else ""
		if not path.begins_with("/tmp/") and not path.begins_with("/private/tmp/"):
			push_error("Refusing a test against live saves: " + name_value)
			get_tree().quit(2)
			return
	TimeManager.set_process(false)
	GameSession.set_process(false)
	get_tree().create_timer(20).timeout.connect(func(): push_error("Lock test timed out"); get_tree().quit(2))
	call_deferred("run")

func card_for(id: String) -> Button:
	for card: Button in journal.page_content.find_children("CardSlot*", "Button", true, false):
		if card.get_meta("cocktail_id", "") == id:
			return card
	return null

func click_at(point: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.position = point
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	get_viewport().push_input(down, true)
	var up := down.duplicate()
	up.pressed = false
	get_viewport().push_input(up, true)

func hover_at(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)

func popup_label(node: Node, expected: String) -> Label:
	if node is Label and node.text == expected and node.is_visible_in_tree():
		return node as Label
	for child: Node in node.get_children(true):
		var found := popup_label(child, expected)
		if found != null:
			return found
	return null

func run() -> void:
	check(MenuCatalog.reset_game() and Supplies.reset_game(), "Private fixture starts with no materials or unlocked drinks")
	journal = load("res://scenes/codex.tscn").instantiate()
	add_child(journal)
	await get_tree().create_timer(0.15).timeout
	check(not journal.allow_locked_details, "Production setting forbids locked detail previews")
	var card := card_for(RECIPE)
	check(card != null and card.disabled and card.is_locked, "Locked card is present and disabled")
	if card == null:
		finish()
		return
	check(card.mouse_default_cursor_shape == Control.CURSOR_ARROW, "Locked card uses a plain arrow cursor")
	var names: Array[String] = []
	for item: Dictionary in Supplies.missing_recipe_requirements(RECIPE).ingredients:
		names.append(str(item.name))
	var expected := "缺少：\n" + "\n".join(names)
	check(card.tooltip_text == expected and names.size() == 3, "Tooltip contains exactly the three missing item names")
	check(not card.tooltip_text.contains("金汤力") and not card.tooltip_text.contains("冰") and not card.tooltip_text.contains("器具"), "Tooltip contains no drink title, ice or equipment")
	hover_at(card.get_global_rect().get_center())
	await get_tree().create_timer(0.85).timeout
	check(get_viewport().gui_get_hovered_control() == card, "Native hover reaches a disabled recipe card")
	check(card.get_tooltip(card.size / 2) == expected, "Disabled card resolves the native tooltip text")
	var popup := popup_label(get_tree().root, expected)
	check(popup != null, "Godot displays the default tooltip popup for a disabled card")
	click_at(card.get_global_rect().get_center())
	await get_tree().process_frame
	check(journal.detail_id.is_empty(), "Native click cannot open locked details")
	journal.show_detail(RECIPE)
	check(journal.detail_id.is_empty(), "Direct show_detail call also obeys the lock guard")
	check(Supplies.purchase(MATERIALS[0]), "Private fixture purchases gin")
	await get_tree().process_frame
	card = card_for(RECIPE)
	names.clear()
	for item: Dictionary in Supplies.missing_recipe_requirements(RECIPE).ingredients:
		names.append(str(item.name))
	expected = "缺少：\n" + "\n".join(names)
	check(card.disabled and card.tooltip_text == expected and names.size() == 2, "Purchase refreshes the missing-only tooltip without allowing entry")
	check(not card.tooltip_text.contains("伦敦干金酒"), "Already purchased material disappears from the tooltip")
	check(Supplies.purchase(MATERIALS[1]) and Supplies.purchase(MATERIALS[2]), "Private fixture buys the remaining required materials")
	await get_tree().process_frame
	card = card_for(RECIPE)
	check(MenuCatalog.get_recipe(RECIPE).unlocked and not card.disabled, "Buying all required materials permanently enables the card")
	check(card.tooltip_text == "新解锁 · 打开酒谱查看后消除提示" and card.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "Newly unlocked card uses its discovery hint and hand cursor")
	click_at(card.get_global_rect().get_center())
	await get_tree().process_frame
	check(journal.detail_id == RECIPE, "Native click opens only the now-unlocked recipe")
	check(Supplies.consume(MATERIALS[1], Supplies.total_remaining(MATERIALS[1])), "Private fixture exhausts tonic water")
	await get_tree().process_frame
	var statuses: Array[String] = []
	for label: Label in journal.page_content.find_children("IngredientStatus", "Label", true, false):
		statuses.append(label.text)
	check(MenuCatalog.get_recipe(RECIPE).unlocked and statuses.has("已用完"), "Stock exhaustion preserves the unlock and updates detail availability")
	journal.close_detail()
	await get_tree().process_frame
	card = card_for(RECIPE)
	check(not card.disabled and card.tooltip_text == "查看酒谱", "An exhausted ingredient never relocks a discovered recipe")
	finish()

func finish() -> void:
	print("CODEX LOCK HOVER: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks)")
	get_tree().quit(0 if failures.is_empty() else 1)
