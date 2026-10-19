extends "res://tests/verify_workbench_scene.gd"
func run() -> void:
	SlotWallet.balance=200000
	var ids:=["last_word","mojito","gin_and_tonic","long_island_iced_tea","manhattan"]
	for id in ids:
		var recipe:=MenuCatalog.get_recipe(id)
		for ingredient in recipe.ingredients:
			if MenuCatalog._is_ice(ingredient): continue
			var sku: String=ingredient.sku_id
			var before: float=Supplies.total_remaining(sku); var money:=SlotWallet.balance; var quote:=Supplies.quote_purchase(sku)
			check(quote.ok and Supplies.purchase(sku),"real shop purchase "+sku)
			check(SlotWallet.balance==money-quote.total and Supplies.total_remaining(sku)>before,"single debit and inventory gain")
		check(MenuCatalog.get_recipe(id).unlocked,"all ingredients unlock classic "+id)
	for id in ["character_milo","character_ada","character_hank","childhood_keepsake"]:
		check(not MenuCatalog.get_recipe(id).unlocked,"shopping never bypasses special reward "+id)
	for item in Supplies.list_shop_items(): check(item.storage_mode!="permanent","equipment and glasses absent from shop")
	var stock: Dictionary=Supplies.inventory.serialize().duplicate(true); var money:=SlotWallet.balance
	check(Supplies.load_state() and Supplies.inventory.serialize()==stock and SlotWallet.balance==money,"stock reload does not duplicate purchase")
	print("STORY SHOP BRIDGE: %d checks, %d failures" % [count,failures.size()]); get_tree().quit(0 if failures.is_empty() else 1)
