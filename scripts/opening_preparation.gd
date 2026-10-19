extends RefCounted
## Quantity checks for opening night. Discovery/unlock checks are not stock checks.

static func report(recipe_id: String) -> Dictionary:
	var recipe: Dictionary = MenuCatalog.get_recipe(recipe_id)
	var result := {"ready":false,"rows":[],"cost":0,"message":"","recipe":recipe}
	if recipe.is_empty():
		result.message = "还没有这款酒的配方。"
		return result
	var amounts: Dictionary = {}
	for row: Dictionary in recipe.get("ingredients", []):
		if not row.get("required",true) or MenuCatalog._is_ice(row): continue
		var sku := str(row.get("sku_id",""))
		var amount := float(row.get("inventory_amount",row.get("amount",0)))
		if sku.is_empty() or amount <= 0:
			result.message = "这款配方的用量尚未完整，先选另一款。"
			return result
		amounts[sku] = float(amounts.get(sku,0)) + amount
	result.ready = not amounts.is_empty()
	for sku: String in amounts:
		var item: Dictionary = Supplies.get_item(sku)
		if item.is_empty():
			result.ready = false
			result.message = "部分材料暂未在商店登记，请选另一款。"
			continue
		var remaining := Supplies.total_remaining(sku)
		var missing := maxf(0,float(amounts[sku])-remaining)
		var pack := float(item.package.get("container_capacity",0)) if item.storage_mode=="container" else float(item.package.get("purchase_quantity",1))
		var packages := ceili(missing/maxf(1,pack))
		var price := Supplies.get_unit_price(sku)
		if missing > 0: result.ready = false
		if missing > 0 and (price < 0 or not item.get("shop_enabled",true)):
			result.message = "有材料目前无法购买，请选另一款。"
		var cost := packages * maxi(0,price)
		result.cost += cost
		result.rows.append({"sku":sku,"name":item.name,"required":amounts[sku],"remaining":remaining,"missing":missing,"packages":packages,"cost":cost,"unit":str(item.measurement_unit) if item.storage_mode=="container" else str(item.quantity_unit)})
	# Ice and permanent tools use the existing bar supply policy, never fake purchases.
	var snapshot: Dictionary = WorkbenchSession.recipe_snapshot(recipe)
	if not WorkbenchSession.CUPS.has(WorkbenchSession.recommended_cup(snapshot)):
		result.ready = false
		result.message = "这款配方的杯型暂未接入。"
	return result

static func ready_menu() -> bool:
	for entry: Dictionary in MenuCatalog.entries:
		if report(str(entry.id)).ready: return true
	return false

static func publish(recipe_id: String) -> bool:
	if not report(recipe_id).ready: return false
	for entry: Dictionary in MenuCatalog.entries:
		if entry.id==recipe_id: return true
	var recipe: Dictionary = MenuCatalog.get_recipe(recipe_id)
	var entries: Array = MenuCatalog.entries.duplicate(true)
	entries.append({"id":recipe_id,"price":recipe.reference_price})
	return MenuCatalog.save_menu(entries,MenuCatalog.design)
