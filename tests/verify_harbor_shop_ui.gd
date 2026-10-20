extends Node
## Requires five explicit /tmp save arguments. --screenshots captures GUI runs.
## Test the real home entry and native mouse hit testing; no production fixtures.

const CATEGORIES := ["原酒", "配料", "装饰品"]
const GIN := "sku_gin_london_dry"
const TONIC := "sku_tonic_water"
const LIME := "sku_lime_wedge"
const RECIPE := "gin_and_tonic"
const OUTPUT := "res://../output/harbor-shop-preview"
var failures: Array[String] = []
var checks := 0
var home: Control
var shop: Control
var supplies: Node
var screenshots := false
var layouts: Array = []

func _ready() -> void:
	supplies = get_node_or_null("/root/Supplies")
	var prefixes := ["--game-save=", "--dialogue-save=", "--slot-wallet=", "--menu-save=", "--supplies-save="]
	for prefix: String in prefixes:
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
			push_error("Refusing UI test against a real or missing save service: " + service_name)
			get_tree().quit(2)
			return
	TimeManager.set_process(false)
	GameSession.set_process(false)
	screenshots = "--screenshots" in OS.get_cmdline_user_args()
	call_deferred("run")

func _temporary(path: String) -> bool:
	return path.begins_with("/tmp/") or path.begins_with("/private/tmp/")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

func move_mouse(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)

func tap_at(point: Vector2) -> void:
	# Same-frame taps exercise the animation's input lock before it can finish.
	move_mouse(point)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	get_viewport().push_input(event, true)

func click_at(point: Vector2) -> void:
	move_mouse(point)
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
	# Desktop mouse motion can arrive between rendered frames. Restore the
	# synthetic pointer before release so this remains a click, not a drag-out.
	move_mouse(point)
	get_viewport().push_input(up, true)
	await settle()

func click(control: Control) -> void:
	if not is_instance_valid(control):
		check(false, "A required native click target is missing")
		return
	await click_at(control.get_global_rect().get_center())

func control(name: String) -> Control:
	return shop.find_child(name, true, false) as Control if is_instance_valid(shop) else null

func text(name: String) -> String:
	var label := control(name) as Label
	return label.text if label != null else ""

func finish_page_turn() -> void:
	await get_tree().create_timer(0.4).timeout
	await settle()

func product_ids() -> Array[String]:
	var ids: Array[String] = []
	for node in shop.find_children("Product_*", "Button", true, false):
		if node.is_visible_in_tree():
			ids.append(str(node.name).trim_prefix("Product_"))
	return ids

func select_product(id: String, category: String) -> Control:
	await click(control("Category_" + category))
	while int(shop.get("page")) > 0:
		var previous := control("PreviousPage") as Button
		if previous == null or previous.disabled:
			break
		await click(previous)
		await finish_page_turn()
	var product := control("Product_" + id)
	var count := 0
	while product == null and count < 5:
		var next := control("NextPage") as Button
		if next == null or next.disabled:
			break
		await click(next)
		await finish_page_turn()
		product = control("Product_" + id)
		count += 1
	check(product != null, "Catalogue product is reachable on a shelf: " + id)
	if product != null:
		await click(product)
		check(str(shop.get("selected_id")) == id, "Native product click selects " + id)
	return product

func capture(name: String) -> void:
	if not screenshots or DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.22).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(folder)
	var image := get_viewport().get_texture().get_image()
	check(image != null and image.save_png(folder.path_join(name + ".png")) == OK, "GUI screenshot saved: " + name)

func run() -> void:
	check(supplies != null and supplies.has_method("purchase"), "Shared Supplies purchase service is ready")
	if supplies == null:
		await finish()
		return
	# The caller uses a fresh temporary directory; funding never touches live saves.
	check(bool(supplies.get("writable")), "Temporary supply store is writable")
	SlotWallet.balance = 5000
	SlotWallet.pending = []
	check(SlotWallet.persist(), "Temporary wallet funding is durable")
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	await click(home.find_child("ShopButton", true, false) as Control)
	check(Navigation.current_route == &"shop", "Actual home ShopButton opens the harbor")
	shop = home.active_page
	if not is_instance_valid(shop):
		check(false, "Harbor scene is instantiated")
		await finish()
		return
	for name: String in ["BackButton", "BuyButton", "QuantityPlus", "QuantityMinus", "QuantityLabel", "CapacityLabel", "StockLabel", "TotalLabel", "PageLabel", "BalanceLabel", "NextPage", "PreviousPage"]:
		check(control(name) != null, "Shop exposes native control: " + name)
	check(shop.find_children("Category_*", "Button", true, false).size() == 3 and control("Category_杯型") == null and control("Category_器材") == null, "Three selling categories; default-owned tools and glassware have no shop entry")
	verify_default_equipment()
	await capture("01-harbor-first-page")
	await verify_categories_and_pages()
	await verify_page_animation()
	await verify_shelf_hit_and_hover()
	await verify_purchase_and_stock()
	await verify_recipe_unlock_and_views()
	await verify_current_material_status()
	await verify_reentry_and_saved_state()
	await verify_sizes()
	await finish()

func verify_categories_and_pages() -> void:
	for category: String in CATEGORIES:
		await click(control("Category_" + category))
		check(str(shop.get("category")) == category and int(shop.get("page")) == 0, "Native category changes reset the page: " + category)
		var ids := product_ids()
		var expected: Array = supplies.call("list_shop_items", category)
		check(ids.size() == mini(6, expected.size()), "Shelf displays up to six catalogue products: " + category)
		for id: String in ids:
			var item: Dictionary = supplies.call("get_item", id)
			check(str(item.get("category")) == category and str(item.get("kind")) == "ingredient", "Shelf product belongs to active consumable category: " + id)
	await click(control("Category_原酒"))
	var first := product_ids()
	var next := control("NextPage") as Button
	check(next != null and not next.disabled, "Ten base spirits require another shelf page")
	await click(next)
	await finish_page_turn()
	var second := product_ids()
	check(int(shop.get("page")) == 1 and first.size() + second.size() == supplies.call("list_shop_items", "原酒").size(), "Next page exposes the remaining base spirits")
	for id: String in second:
		check(not first.has(id), "Pagination does not repeat products: " + id)
	check((control("NextPage") as Button).disabled, "Last page disables NextPage")
	await capture("02-base-spirits-second-page")
	await click(control("PreviousPage"))
	await finish_page_turn()
	check(int(shop.get("page")) == 0 and product_ids() == first, "PreviousPage restores the first shelf")

func verify_default_equipment() -> void:
	var available: Array = supplies.call("list_shop_items")
	for item: Dictionary in available:
		check(str(item.kind) == "ingredient", "Shop API excludes permanent tools, glassware and ice: " + str(item.id))
	var catalog: RefCounted = supplies.get("catalog")
	for item: Dictionary in catalog.call("list_items"):
		if str(item.kind) in ["equipment", "glassware"]:
			check(bool(supplies.call("is_owned", str(item.id))), "Reusable item is already owned without a purchase: " + str(item.id))

func verify_page_animation() -> void:
	await click(control("Category_原酒"))
	var first := product_ids()
	var shelf_origin: Vector2 = control("ShelfProducts").position
	var selected := str(shop.get("selected_id"))
	var packages_before := int(shop.get("packages"))
	var balance_before := SlotWallet.balance
	var stock_before: Dictionary = supplies.call("get_state", selected)
	tap_at(control("NextPage").get_global_rect().get_center())
	for name: String in ["QuantityPlus", "QuantityMinus", "BuyButton"]:
		check((control(name) as Button).disabled, "Page transition disables native transaction control: " + name)
	for id: String in product_ids():
		check((control("Product_" + id) as Button).disabled, "Page transition prevents selecting a stale shelf product: " + id)
	for i in range(4):
		tap_at(control("NextPage").get_global_rect().get_center())
		tap_at(control("PreviousPage").get_global_rect().get_center())
	if first.size() > 1:
		var other := control("Product_" + first[1])
		if other != null:
			tap_at(other.get_global_rect().get_center())
	tap_at(control("QuantityPlus").get_global_rect().get_center())
	tap_at(control("BuyButton").get_global_rect().get_center())
	check(SlotWallet.balance == balance_before and supplies.call("get_state", selected) == stock_before, "Clicks during fade cannot buy stale products or charge the wallet")
	check(int(shop.get("packages")) == packages_before, "Page transition ignores quantity clicks")
	await get_tree().create_timer(0.18).timeout
	for name: String in ["QuantityPlus", "QuantityMinus", "BuyButton"]:
		check((control(name) as Button).disabled, "Incoming shelf stays locked during fade-in: " + name)
	for id: String in product_ids():
		check((control("Product_" + id) as Button).disabled, "New shelf product stays locked until fade-in completes: " + id)
	tap_at(control("BuyButton").get_global_rect().get_center())
	check(SlotWallet.balance == balance_before, "Fade-in cannot charge the wallet for the new page")
	await finish_page_turn()
	check(int(shop.get("page")) == 1, "Rapid next/previous clicks complete exactly one page turn")
	check(not (control("QuantityPlus") as Button).disabled and not (control("BuyButton") as Button).disabled, "New shelf restores quantity and purchase interaction")
	for id: String in product_ids():
		check(not (control("Product_" + id) as Button).disabled, "Finished transition restores native shelf selection: " + id)
	for i in range(3):
		tap_at(control("NextPage").get_global_rect().get_center())
	await finish_page_turn()
	check(int(shop.get("page")) == 1, "Last-page boundary cannot advance on repeated mouse taps")
	await click(control("PreviousPage"))
	await finish_page_turn()
	for i in range(3):
		tap_at(control("PreviousPage").get_global_rect().get_center())
	await finish_page_turn()
	check(int(shop.get("page")) == 0 and product_ids() == first, "First-page boundary cannot move backward or change products")
	# Cancel once in fade-out and once after the new page has begun fading in.
	for scenario: Dictionary in [{"delay": 0.06, "category": "配料"}, {"delay": 0.19, "category": "装饰品"}]:
		await click(control("Category_原酒"))
		tap_at(control("NextPage").get_global_rect().get_center())
		await get_tree().create_timer(float(scenario.delay)).timeout
		await click(control("Category_" + str(scenario.category)))
		await finish_page_turn()
		check(str(shop.get("category")) == str(scenario.category) and int(shop.get("page")) == 0, "Category change cancels either phase of the old page animation: " + str(scenario.delay))
		var expected: Array = supplies.call("list_shop_items", str(scenario.category))
		var expected_ids: Array[String] = []
		for item: Dictionary in expected.slice(0, 6):
			expected_ids.append(str(item.id))
		check(product_ids() == expected_ids, "Cancelled page cannot replace the chosen category later")
		var shelf := control("ShelfProducts")
		check(shelf != null and shelf.modulate.a > 0.99, "Cancelled animation restores visible shelf opacity")
		check(shelf != null and shelf.position.is_equal_approx(shelf_origin), "Cancelled animation restores the shelf's resting position")
		check(not (control("QuantityPlus") as Button).disabled and not (control("BuyButton") as Button).disabled, "Cancelled animation restores purchase interaction")
		for id: String in product_ids():
			check(not (control("Product_" + id) as Button).disabled, "Cancelled animation restores shelf selection: " + id)
	await click(control("Category_原酒"))

func verify_shelf_hit_and_hover() -> void:
	var ids := product_ids()
	if ids.size() < 2:
		check(false, "Two shelf items are available for independent hit testing")
		return
	await click(control("Product_" + ids[1]))
	var first := control("Product_" + ids[0]) as Button
	var tag := first.get("tag") as Control
	check(tag != null, "Product has a hanging paper tag")
	if tag != null:
		await click_at(tag.get_global_rect().get_center())
		check(str(shop.get("selected_id")) == ids[0], "Upper shelf tag click is not intercepted by the lower shelf")
	for style: String in ["normal", "hover", "pressed", "focus"]:
		check(first.get_theme_stylebox(style) is StyleBoxEmpty, "Shelf interaction adds no large opaque button plate: " + style)
	move_mouse(first.get_global_rect().get_center())
	await get_tree().create_timer(0.2).timeout
	await click(first)
	move_mouse(Vector2(2, 200))
	await get_tree().create_timer(0.22).timeout
	var art := first.get("art") as TextureRect
	check(not first.is_pressed() and not first.is_hovered(), "Mouse release and departure clear shelf press/hover")
	check(art != null and art.modulate.is_equal_approx(Color.WHITE) and art.scale.is_equal_approx(Vector2.ONE), "Art returns to normal after hover/press without residual highlight")

func verify_purchase_and_stock() -> void:
	await select_product(GIN, "原酒")
	var item: Dictionary = supplies.call("get_item", GIN)
	var capacity := float(item.package.container_capacity)
	var price := int(supplies.call("get_unit_price", GIN))
	check(price > 0 and int(shop.get("packages")) == 1, "Gin starts with one purchasable package")
	await click(control("QuantityPlus"))
	check(int(shop.get("packages")) == 2 and text("QuantityLabel").to_int() == 2, "QuantityPlus updates purchase quantity")
	await click(control("QuantityMinus"))
	check(int(shop.get("packages")) == 1 and (control("QuantityMinus") as Button).disabled, "QuantityMinus stops at one package")
	await click(control("QuantityPlus"))
	check(text("TotalLabel").contains(str(price * 2)), "Receipt shows two-package total")
	var before_balance := SlotWallet.balance
	var before: Dictionary = supplies.call("get_state", GIN)
	await click(control("BuyButton"))
	var bought: Dictionary = supplies.call("get_state", GIN)
	check(SlotWallet.balance == before_balance - price * 2, "Native BuyButton deducts exactly the receipt amount")
	check(int(bought.quantity) == int(before.quantity) + 2 and bool(bought.unlocked), "Native purchase adds two packages and unlocks the ingredient")
	check(text("BalanceLabel").contains(str(SlotWallet.balance)), "Balance label follows purchase")
	check(text("CapacityLabel").contains(str(int(capacity))) and text("CapacityLabel").contains("ml"), "Separate capacity line shows bottle size and measure")
	check(text("StockLabel").contains(str(int(bought.quantity))) and text("StockLabel").contains(str(int(capacity))), "Stock line shows current package count and full bottle remainder")
	check(control("StockLabel").get_global_rect().position.y > control("CapacityLabel").get_global_rect().position.y, "Capacity and stock use separate receipt lines")
	check(bool(supplies.call("consume", GIN, 100.0)), "Temporary stock fixture uses 100 ml through the durable supply API")
	await settle()
	var used: Dictionary = supplies.call("get_state", GIN)
	check(is_equal_approx(float(used.current_remaining), capacity - 100.0), "Bottle keeps its opened remainder")
	check(text("StockLabel").contains(str(int(capacity - 100.0))) and text("StockLabel").contains("ml"), "Receipt refreshes the actual opened bottle remainder")
	check(is_equal_approx(float(MenuCatalog.inventory.get(GIN, 0)), float(supplies.call("total_remaining", GIN))), "Recipe stock snapshot follows shared remaining stock")
	await capture("03-purchase-and-opened-remainder")

func labels_under(node: Node) -> String:
	var values: Array[String] = []
	for label in node.find_children("*", "Label", true, false):
		values.append(label.text)
	return "\n".join(values)

func journal_card(journal: Control) -> Button:
	for card in journal.find_children("CardSlot*", "Button", true, false):
		if str(card.get_meta("cocktail_id", "")) == RECIPE:
			return card as Button
	return null

func return_home() -> void:
	var previous_route := str(Navigation.current_route)
	if Navigation.current_route == &"shop":
		await click(control("BackButton"))
	elif Navigation.current_route != &"home":
		await click(home.find_child("HomeButton", true, false) as Control)
	# Three fast headless frames are shorter than a rendered route transition.
	# Let the outgoing page and deferred layout settle before the next native tap.
	await get_tree().create_timer(0.2).timeout
	await settle()
	check(Navigation.current_route == &"home" and home.active_page == null, "Native navigation restores the tavern after %s (actual route: %s)" % [previous_route, Navigation.current_route])

func reopen_shop() -> void:
	await return_home()
	var entry := home.find_child("ShopButton", true, false) as Control
	check(entry != null and entry.is_visible_in_tree(), "Shop entry is visible after returning from recipe views")
	await click(entry)
	await get_tree().create_timer(0.2).timeout
	await settle()
	shop = home.active_page
	var actual_page := str(shop.get_script().resource_path) if is_instance_valid(shop) else "none"
	check(is_instance_valid(shop) and Navigation.current_route == &"shop", "Native shop entry remains available after recipe views (actual route: %s, page: %s, entry rect: %s)" % [Navigation.current_route, actual_page, entry.get_global_rect() if entry != null else Rect2()])

func verify_recipe_unlock_and_views() -> void:
	var recipe: Dictionary = MenuCatalog.get_recipe(RECIPE)
	var progress: Dictionary = MenuCatalog.ingredient_progress(recipe)
	check(not bool(recipe.unlocked) and progress.owned == 1 and progress.total == 3, "Gin purchase updates one of three recipe ingredients without prematurely unlocking")
	await return_home()
	await click(home.find_child("CodexButton", true, false) as Control)
	check(Navigation.current_route == &"codex", "Native journal entry opens the recipe collection")
	var journal: Control = home.active_page
	var card := journal_card(journal)
	check(card != null and bool(card.get("is_locked")), "Journal reflects the still-locked recipe after a partial purchase")
	if card != null:
		check(labels_under(card).contains("原料 1 / 3"), "Journal ingredient counter follows the partial stock")
		check(card.disabled, "Locked recipe card cannot open its detail")
		move_mouse(card.get_global_rect().get_center())
		await get_tree().create_timer(0.55).timeout
		var tooltip := card.tooltip_text
		for id: String in [TONIC, LIME]:
			var missing: Dictionary = supplies.call("get_item", id)
			check(tooltip.contains(str(missing.name)), "Locked-card hover identifies the actual missing ingredient: " + str(missing.name))
		var owned: Dictionary = supplies.call("get_item", GIN)
		check(not tooltip.contains(str(owned.name)) and not tooltip.contains("冰"), "Locked-card hover omits owned gin and automatically available ice")
		var catalog: RefCounted = supplies.get("catalog")
		for item: Dictionary in catalog.call("list_items", "器材"):
			check(not tooltip.contains(str(item.name)), "Locked-card hover omits default equipment: " + str(item.name))
		await click(card)
		check(str(journal.get("detail_id")).is_empty() and journal.find_child("CocktailDetail", true, false) == null, "Native locked-card click leaves the overview and does not reveal recipe details")
	await capture("04-journal-partial-stock")
	await reopen_shop()
	for id: String in [TONIC, LIME]:
		var item: Dictionary = supplies.call("get_item", id)
		await select_product(id, str(item.category))
		var balance_before := SlotWallet.balance
		var price := int(supplies.call("get_unit_price", id))
		await click(control("BuyButton"))
		check(SlotWallet.balance == balance_before - price and bool(supplies.call("is_unlocked", id)), "Native material purchase contributes to recipe unlocking: " + id)
	recipe = MenuCatalog.get_recipe(RECIPE)
	progress = MenuCatalog.ingredient_progress(recipe)
	check(bool(recipe.unlocked) and progress.owned == 3 and progress.total == 3, "Buying all required consumables unlocks the recipe with default equipment")
	await return_home()
	await click(home.find_child("CodexButton", true, false) as Control)
	journal = home.active_page
	card = journal_card(journal)
	check(card != null and not bool(card.get("is_locked")), "Journal shows the purchased recipe as unlocked")
	if card != null:
		check(labels_under(card).contains("原料 3 / 3") and labels_under(card).contains("已点亮"), "Journal displays complete material progress and unlocked status")
		var art := card.find_child("DrinkPicture", true, false) as TextureRect
		check(art != null and art.material == null, "Unlocked journal art removes its locked rendering material")
	await capture("05-journal-unlocked")
	await return_home()
	await click(home.find_child("MenuButton", true, false) as Control)
	check(Navigation.current_route == &"menu", "Native menu entry opens the real drink selector")
	var menu: Control = home.active_page
	var menu_card := menu.find_child("Recipe_" + RECIPE, true, false) as Button
	check(not bool(menu.get("sample_mode")) and menu_card != null and not menu_card.disabled, "Purchased recipe appears in the real menu, outside samples")
	if menu_card != null:
		verify_menu_art_inside(menu_card)
		await click(menu_card)
		var selected: Array = menu.get("selected")
		check(selected.any(func(entry: Dictionary): return str(entry.id) == RECIPE), "Native drink card can select the unlocked recipe for tonight's menu")
		verify_menu_art_inside(menu.find_child("Recipe_" + RECIPE, true, false) as Button)
	await capture("06-menu-unlocked-recipe")
	await reopen_shop()

func verify_menu_art_inside(card: Button) -> void:
	check(card != null, "Real menu recipe card remains present after selection")
	if card == null:
		return
	var art_nodes := card.find_children("*", "TextureRect", true, false)
	check(not art_nodes.is_empty(), "Real menu recipe card contains its supplied drink illustration")
	for node in art_nodes:
		var art := node as TextureRect
		check(art.texture != null and inside(art, card.get_global_rect()), "Original high-resolution drink art stays within the actual menu card")

func ingredient_row(detail: Control, id: String) -> Control:
	var ingredients := detail.find_child("Ingredients", true, false)
	if ingredients != null:
		for row in ingredients.get_children():
			if str(row.get_meta("sku_id", "")) == id:
				return row as Control
	return null

func verify_current_material_status() -> void:
	var balance_before := SlotWallet.balance
	var gin_available := float(supplies.call("total_remaining", GIN))
	var tonic_available := float(supplies.call("total_remaining", TONIC))
	check(gin_available > 10 and tonic_available > 0, "Purchased stock is available for current-material verification")
	check(bool(supplies.call("consume", GIN, gin_available - 10.0)), "Temporary gin stock is reduced to 10 ml through the supply API")
	check(bool(supplies.call("consume", TONIC, tonic_available)), "Temporary tonic stock is consumed through the supply API")
	await settle()
	check(SlotWallet.balance == balance_before and is_equal_approx(float(MenuCatalog.inventory.get(GIN, 0)), 10.0) and is_zero_approx(float(MenuCatalog.inventory.get(TONIC, 0))), "Consumption updates shared remaining stock without charging coins")
	check(bool(MenuCatalog.get_recipe(RECIPE).unlocked), "An unlocked recipe remains discovered when materials become insufficient")
	await return_home()
	await click(home.find_child("CodexButton", true, false) as Control)
	var journal: Control = home.active_page
	var card := journal_card(journal)
	check(card != null and not bool(card.get("is_locked")), "Journal keeps the recipe unlocked after its materials run low")
	if card == null:
		await reopen_shop()
		return
	await click(card)
	var detail := journal.find_child("CocktailDetail", true, false) as Control
	check(detail != null and str(journal.get("detail_id")) == RECIPE, "Native journal card opens the current recipe detail")
	if detail == null:
		await reopen_shop()
		return
	for condition: Dictionary in [{"id": GIN, "status": "余量不足", "amount": "10"}, {"id": TONIC, "status": "已用完", "amount": "0"}, {"id": LIME, "status": "已有", "amount": "20"}]:
		var row := ingredient_row(detail, str(condition.id))
		var status := row.find_child("IngredientStatus", true, false) as Label if row != null else null
		check(status != null and status.text == str(condition.status), "Recipe detail distinguishes actual material status: %s = %s" % [condition.id, condition.status])
		check(row != null and row.tooltip_text.contains("当前库存") and row.tooltip_text.contains(str(condition.amount)), "Recipe ingredient tooltip includes current inventory: " + str(condition.id))
	await capture("08-journal-current-materials")
	await click(detail.find_child("BackToCodex", true, false) as Control)
	check(str(journal.get("detail_id")).is_empty(), "Native detail return restores the journal overview")
	var next := journal.find_child("NextPage", true, false) as Control
	tap_at(next.get_global_rect().get_center())
	await get_tree().create_timer(0.06).timeout
	check(bool(journal.get("turning")), "Native journal page turn is active before inventory changes")
	var incoming: Control = journal.get("page_content")
	var incoming_id := incoming.get_instance_id()
	check(bool(supplies.call("consume", LIME, 1.0)), "A real stock update reaches the journal during its page animation")
	check(bool(journal.get("turning")) and bool(journal.get("_catalog_refresh_pending")), "Inventory change queues a journal refresh without interrupting its animation")
	await get_tree().create_timer(1.0).timeout
	await settle()
	var refreshed: Control = journal.get("page_content")
	check(not bool(journal.get("turning")) and not bool(journal.get("_catalog_refresh_pending")) and int(journal.get("page_index")) == 1, "Journal completes the turn and clears its queued inventory refresh")
	check(refreshed != null and refreshed.is_inside_tree() and refreshed.get_instance_id() != incoming_id, "Finished journal turn replaces the page with the current catalogue state")
	check(bool(MenuCatalog.get_recipe(RECIPE).unlocked), "Consumption during a page turn preserves the discovered recipe")
	await reopen_shop()

func verify_reentry_and_saved_state() -> void:
	var stock_before: Dictionary = supplies.call("get_state", GIN)
	var balance_before := SlotWallet.balance
	await click(control("BackButton"))
	check(Navigation.current_route == &"home", "Native BackButton returns to the tavern")
	await click(home.find_child("ShopButton", true, false) as Control)
	shop = home.active_page
	check(Navigation.current_route == &"shop" and SlotWallet.balance == balance_before and supplies.call("get_state", GIN) == stock_before, "Returning and re-entering preserves stock and wallet")
	await select_product(GIN, "原酒")
	check(bool(MenuCatalog.get_recipe(RECIPE).unlocked), "Reopened shop preserves the recipe unlocked by purchases")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(supplies.get("save_path"))))
	var wallet_saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(SlotWallet.save_path))
	check(saved is Dictionary and saved.get("inventory", {}).get("items", {}).get(GIN, {}) == JSON.parse_string(JSON.stringify(stock_before)), "Purchase and opened remainder are durably stored in the isolated supply file")
	check(wallet_saved is Dictionary and int(wallet_saved.get("balance", -1)) == balance_before, "Isolated wallet file contains the committed balance")

func inside(control_node: Control, bounds: Rect2) -> bool:
	if control_node == null:
		return false
	var rect := control_node.get_global_rect()
	return rect.position.x >= bounds.position.x - 1 and rect.position.y >= bounds.position.y - 1 and rect.end.x <= bounds.end.x + 1 and rect.end.y <= bounds.end.y + 1

func verify_sizes() -> void:
	await select_product(GIN, "原酒")
	for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(800, 450), Vector2i(1280, 720), Vector2i(1024, 768)]:
		get_tree().root.size = dimensions
		await settle()
		var bounds := Rect2(Vector2.ZERO, home.size)
		var stage := home.get_node("%Stage") as Control
		check(inside(stage, bounds), "Scaled 1600x900 Stage stays inside the viewport: " + str(dimensions))
		for name: String in ["BackButton", "Category_原酒", "Category_装饰品", "BuyButton", "QuantityPlus", "QuantityMinus", "CapacityLabel", "StockLabel", "TotalLabel", "NextPage", "PreviousPage"]:
			check(inside(control(name), bounds), "Interactive/receipt control remains within screen at %s: %s" % [dimensions, name])
		for id: String in product_ids():
			check(inside(control("Product_" + id), bounds), "Shelf slot remains within screen: %s at %s" % [id, dimensions])
		await click(control("QuantityPlus"))
		check(int(shop.get("packages")) == 2, "Scaled QuantityPlus remains clickable: " + str(dimensions))
		await click(control("QuantityMinus"))
		check(int(shop.get("packages")) == 1, "Scaled QuantityMinus remains clickable: " + str(dimensions))
		layouts.append({"window": [dimensions.x, dimensions.y], "logical_size": [home.size.x, home.size.y], "stage_rect": [stage.get_global_rect().position.x, stage.get_global_rect().position.y, stage.get_global_rect().size.x, stage.get_global_rect().size.y]})
		await capture("07-size-%dx%d" % [dimensions.x, dimensions.y])

func finish() -> void:
	var folder := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(folder)
	var report := FileAccess.open(folder.path_join("ui-verification.json"), FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "layouts": layouts, "renderer": DisplayServer.get_name(), "screenshots_requested": screenshots, "save_paths": {"wallet": SlotWallet.save_path, "supplies": str(supplies.get("save_path")) if supplies != null else ""}}, "\t"))
		report.close()
	SaloonAudio.set_process(false)
	if is_instance_valid(SaloonAudio.fade):
		SaloonAudio.fade.kill()
	for player in SaloonAudio.players:
		player.stop()
		player.stream = null
	SaloonAudio._streams.clear()
	if is_instance_valid(home):
		home.queue_free()
		await settle()
	print("HARBOR SHOP UI: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size(), " (", checks, " checks; native mouse entry, shelves, purchase, reentry, sizes)")
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
