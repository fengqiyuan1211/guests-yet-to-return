extends RefCounted
## Recipe quantities; stock units stay authoritative. Legacy records are read as copies.
static func number(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")

static func ingredient(row: Dictionary) -> Dictionary:
	var out := row.duplicate(true)
	var unit := str(row.get("inventory_unit", row.get("unit", "")))
	var value: Variant = row.get("inventory_amount")
	if value != null and unit in ["ml", "g", "piece", "sprig"]:
		if row.get("unit") != unit or row.get("amount") != value:
			if not out.has("source_quantity"): out.source_quantity={"amount":row.get("amount"),"unit":row.get("unit")}
		out.amount=value; out.unit=unit; out.conversion_factor=1.0
	return out

static func unit_text(row: Dictionary) -> String:
	var unit := str(row.get("unit", ""))
	if unit == "sprig": return "枝"
	if unit == "piece":
		var id := str(row.get("sku_id", "")); var title := str(row.get("name", ""))
		if "leaf" in id or "slice" in id or "叶" in title or title.ends_with("片"): return "片"
		if "cherry" in id or "樱桃" in title: return "颗"
		return "块"
	return unit

static func amount_text(row: Dictionary) -> String:
	var normalized := ingredient(row)
	return number(float(normalized.get("amount",0)))+" "+unit_text(normalized)

static func ice_kind(row: Dictionary) -> String:
	if row.get("kind") in ["cube","crushed"]: return row.kind
	return "crushed" if "crushed" in str(row.get("sku_id","")) or "碎" in str(row.get("name","")) else "cube"

static func ice(row: Dictionary) -> Dictionary:
	var out := row.duplicate(true)
	out.kind=ice_kind(row)
	out.name="碎冰" if out.kind=="crushed" else "标准方冰"
	out.sku_id="sku_ice_crushed" if out.kind=="crushed" else "sku_ice_standard_cube"
	out.use=str(row.get("use","出品冰"))
	out.inventory_policy="excluded_from_ingredient_inventory"
	return out

static func ice_rows(rows: Array) -> Array:
	var result: Array=[]
	var indices: Dictionary={}
	for row: Dictionary in rows:
		var item:=ice(row)
		var key:=str(item.use)+":"+str(item.kind)+":"+str(item.get("unit",""))
		if indices.has(key): result[indices[key]].amount+=float(item.amount)
		else: indices[key]=result.size(); result.append(item)
	return result

static func ice_text(row: Dictionary, portions:=false) -> String:
	var item:=ice(row)
	var text:="%s · %s %s %s" % [item.use,item.name,number(float(item.amount)),str(item.get("unit","g"))]
	if portions and item.get("unit")=="g":
		text+="（%s 份）" % number(float(item.amount)/50.0)
	return text

static func recipe(value: Dictionary) -> Dictionary:
	var out:=value.duplicate(true)
	for field in ["ingredients","ingredient_rows"]:
		if out.get(field) is Array:
			for i in range(out[field].size()): out[field][i]=ingredient(out[field][i])
	out.ice=ice_rows(out.get("ice",[]))
	return out
