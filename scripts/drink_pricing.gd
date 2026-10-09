extends RefCounted
## One recipe-cost contract for classics, legendary recipes and saved DIY drinks.
static func quote(recipe: Dictionary) -> Dictionary:
	var rules: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/drink_pricing.json"))
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/supplies/catalog.json"))
	var prices: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/supplies/shop_prices.json")).prices
	var items: Dictionary={}
	for item: Dictionary in catalog.items: items[item.id]=item
	var rows: Variant=recipe.get("ingredients",[])
	if not rows is Array or rows.is_empty(): return {"ok":false,"message":"配方缺少用料，暂不能定价。"}
	var cost:=0.0
	var lines: Array=[]
	for row: Dictionary in rows:
		var id:=str(row.get("sku_id",""))
		if id.begins_with("sku_ice_") or row.get("use")=="冰": continue
		if not items.has(id) or not prices.has(id): return {"ok":false,"message":"原料尚未配置价格："+id}
		var item: Dictionary=items[id]
		var package: Dictionary=item.package
		var units:=float(package.purchase_quantity)
		if item.storage_mode=="container": units*=float(package.container_capacity)
		var amount: Variant=row.get("inventory_amount",row.get("amount"))
		var unit: String=str(row.get("inventory_unit",row.get("unit","")))
		if unit!=str(item.measurement_unit) or not (amount is float or amount is int) or not is_finite(float(amount)) or float(amount)<=0 or units<=0:
			return {"ok":false,"message":"原料单位或用量不完整："+id}
		var subtotal:=float(prices[id])*float(amount)/units
		cost+=subtotal
		lines.append({"sku_id":id,"amount":amount,"unit":unit,"cost":subtotal})
	return {"ok":true,"version":rules.version,"cost":cost,"multiplier":rules.multiplier,"price":maxi(int(rules.minimum_price),floori(cost*float(rules.multiplier)+0.0000001)),"lines":lines}
