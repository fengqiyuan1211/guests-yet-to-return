extends RefCounted
## Read-only comparisons against the frozen recipe, including non-liquid ingredients.
static func text_for(session: Dictionary, service: Node) -> String:
	var recipe: Dictionary=session.get("recipe",service.RECIPE)
	var expected: Dictionary={}
	for row in recipe.get("ingredient_rows",[]):
		expected[row.sku_id]=row.get("inventory_amount")
	if not recipe.has("ingredient_rows"):
		for id in recipe.ingredients: expected[service.MATERIALS[id].sku_id]=recipe.ingredients[id]
	var changes: Array[String]=[]
	var definitions: Dictionary=service.MATERIALS.duplicate()
	definitions.merge(service.SOLIDS)
	definitions.merge(service.GARNISHES)
	for id in definitions:
		var definition: Dictionary=definitions[id]
		var used:=float(session.get("consumed",{}).get(definition.sku_id,session.get("withdrawn",{}).get(id,0)))
		if used<=0: continue
		var unit:=str(definition.get("unit","ml"))
		if not expected.has(definition.sku_id): changes.append("＋额外 %s %s %s" % [definition.name,service.format_amount(used),unit])
		elif expected[definition.sku_id]!=null:
			var difference:=used-float(expected[definition.sku_id])
			if difference<-.001: changes.append("↓ %s 待加 %s %s" % [definition.name,service.format_amount(-difference),unit])
			elif difference>.001: changes.append("↑ %s 多取 %s %s" % [definition.name,service.format_amount(difference),unit])
	# Keep production ice and serving ice distinct, even after filtering.
	var expected_ice: Dictionary={}
	for row in recipe.get("ice",[]):
		var kind: String="crushed" if str(row.get("sku_id","")).contains("crushed") else "cube"
		var purpose:=str(row.get("use","出品冰"))
		expected_ice[purpose+":"+kind]=float(row.amount)
	var actual_ice: Dictionary={}
	for action in session.get("actions",[]):
		if action.kind!="ice": continue
		var payload: Dictionary=action.payload
		var purpose: String="出品冰" if payload.get("vessel","glass")=="glass" else "制作冰"
		var key:=purpose+":"+str(payload.get("ice","cube"))
		actual_ice[key]=float(actual_ice.get(key,0))+float(action.get("mass_g",40))
	var ice_lines: Array[String]=[]
	for key in actual_ice:
		var parts: PackedStringArray=key.split(":")
		var name: String="方冰" if parts[1]=="cube" else "碎冰"
		var amount:=float(actual_ice[key])
		ice_lines.append("%s · %s已加 %s g%s" % [parts[0],name,service.format_amount(amount)," / 配方 %s g" % service.format_amount(expected_ice[key]) if expected_ice.has(key) else ""])
		if not expected_ice.has(key): changes.append("＋额外%s %s %s g" % [parts[0],name,service.format_amount(amount)])
		elif amount>expected_ice[key]: changes.append("↑ %s%s多加 %s g" % [parts[0],name,service.format_amount(amount-expected_ice[key])])
	var lost: Dictionary=session.get("waste",{})
	for material in lost:
		changes.append("已倒掉 %s %s ml" % [service.MATERIALS[material].name,service.format_amount(lost[material])])
	var original: String=service.recipe_note(session)
	var split:=original.find("\n\n")
	var ingredients:=original.substr(0,split) if split>=0 else original
	var instructions:=original.substr(split) if split>=0 else ""
	var result:=ingredients.replace("[","[lb]")
	if not ice_lines.is_empty(): result+="\n"+"\n".join(ice_lines).replace("[","[lb]")
	if not changes.is_empty(): result+="\n\n[b][color=#883e26][font_size=18]本杯调整\n"+"\n".join(changes).replace("[","[lb]")+"[/font_size][/color][/b]"
	result+=instructions.replace("[","[lb]")
	return result
