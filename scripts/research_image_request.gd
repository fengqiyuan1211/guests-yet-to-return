extends RefCounted
## Build artwork requests from what is physically in the finished glass, never the target recipe.
static func build(session: Dictionary, title: String, story: String) -> Dictionary:
	var result: Dictionary=session.result
	var glass: Dictionary=result.contents
	var ingredients: Array=[]
	var retained: Array=[]
	for group in ["contents","solids"]:
		for material in glass.get(group,{}):
			var definition: Dictionary=WorkbenchSession.MATERIALS.get(material,WorkbenchSession.SOLIDS.get(material,{}))
			if definition.is_empty(): continue
			var item:=Supplies.get_item(str(definition.sku_id))
			var unit: String="ml" if group=="contents" else str(item.get("measurement_unit","g"))
			ingredients.append({"sku_id":definition.sku_id,"name":definition.name,"amount":glass[group][material],"unit":unit,"use":"基酒" if item.get("contains_alcohol",false) else "配料"})
			if group=="solids" and material in ["sku_mint_leaf","sku_lime_wedge"]: retained.append(definition.sku_id)
	var decorations: Dictionary={}
	for material in WorkbenchSession.garnishes(glass): decorations[material]=int(decorations.get(material,0))+1
	for material in decorations:
		var definition: Dictionary=WorkbenchSession.GARNISHES[material]
		var item:=Supplies.get_item(str(definition.sku_id))
		ingredients.append({"sku_id":definition.sku_id,"name":definition.name,"amount":decorations[material],"unit":str(item.get("measurement_unit","piece")),"use":"装饰"})
	var ice: Array=[]
	var totals: Dictionary={}
	for batch: Dictionary in WorkbenchSession.ice_batches(glass): totals[batch.kind]=float(totals.get(batch.kind,0))+float(batch.get("mass_g",batch.volume))
	for kind in totals: ice.append({"name":"标准方冰" if kind=="cube" else "碎冰","amount":totals[kind],"unit":"g","use":"出品冰"})
	var techniques: Array[String]=[]
	for action: Dictionary in result.get("actions",[]):
		var label: String={"shake":"摇和","stir":"搅拌","muddle":"轻压","filter":"过滤"}.get(action.kind,"")
		if not label.is_empty() and label not in techniques: techniques.append(label)
	var cup: String={"highball":"高球杯","rocks":"古典杯","coupe":"碟形杯","glass_cocktail_glass":"鸡尾酒杯","glass_balloon_glass":"球形杯"}.get(result.cup,"高球杯")
	return {"schema_version":1,"style_id":"saloon-cocktail-cutout-v1","recipe":{"id":str(result.drink_id),"revision":1,"name":title,"story":story,"ingredients":ingredients,"glass":cup,"preparation":"→".join(techniques) if not techniques.is_empty() else "杯中兑和","ice":ice,"retained_solids":retained}}
