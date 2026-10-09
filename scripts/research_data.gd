extends RefCounted
## Research lives inside the existing atomic stock/workbench save, never a second wallet.
const Sensory=preload("res://scripts/sensory_model.gd")
const CONFIG_PATH := "res://data/research.json"
const ATTRS := ["alcohol_intensity", "sweetness", "sourness", "bitterness"]

static func config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))

static func fresh() -> Dictionary:
	return {"version":1,"inspiration":int(config().initial_inspiration),"serial":0,"recipes":{},"saved_drinks":{},"acquired":{},"mastered":{},"versions":{},"archived":{},"memory_matches":{},"story_items":{}}

static func whole(value: Variant, maximum: int = 1000000000) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= maximum and value == floor(value)

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1: return false
	if not whole(value.get("inspiration")) or not whole(value.get("serial")): return false
	for key in ["recipes","saved_drinks","acquired","mastered"]:
		if not value.get(key) is Dictionary: return false
	for key in ["versions","archived"]:
		if not value.get(key,{}) is Dictionary: return false
	for id in value.get("versions",{}):
		if not id is String or not value.versions[id] is Array: return false
		var prior:=0
		for record in value.versions[id]:
			if not record is Dictionary or not whole(record.get("version")) or int(record.version)<=prior: return false
			prior=int(record.version)
			var check_state:={"version":1,"inspiration":0,"serial":0,"recipes":{id:record},"saved_drinks":{},"acquired":{},"mastered":{}}
			if not valid(check_state): return false
	for id in value.get("archived",{}):
		if not id is String or value.archived[id]!=true or value.recipes.has(id): return false
	if not value.get("memory_matches", {}) is Dictionary: return false
	for id in value.get("memory_matches", {}):
		if not preload("res://scripts/stick_memory_rules.gd").valid_result(value.memory_matches[id]) or value.memory_matches[id].match_id != id: return false
	if not value.get("story_items", {}) is Dictionary: return false
	for id in value.get("story_items", {}):
		var item: Variant = value.story_items[id]
		if id != preload("res://scripts/stick_memory_rules.gd").ITEM_ID or not item is Dictionary: return false
		if item.get("owned") != true or item.get("unlocked") != true or item.get("quantity") != 1 or not item.get("awarded_by") is String: return false
		if not value.get("memory_matches", {}).has(item.awarded_by) or value.memory_matches[item.awarded_by].outcome != "win": return false
	if not value.get("legendary_images", {}) is Dictionary: return false
	for image_record in value.get("legendary_images", {}).values():
		if not valid_image(image_record): return false
	for id in value.recipes:
		var r: Variant = value.recipes[id]
		if not id is String or not r is Dictionary or r.get("id") != id or not id.begins_with("diy_"): return false
		if not r.get("name") is String or r.name.is_empty() or r.name.length() > 40: return false
		if not r.get("english_name") is String or r.english_name.length() > 70 or not r.get("notes") is String or r.notes.length() > 500: return false
		if not whole(r.get("version")) or r.version < 1 or not r.get("drink_id") is String or not r.get("result") is Dictionary: return false
		if r.has("image_generation") and not valid_image(r.image_generation): return false
		if not r.get("ingredients") is Array or not r.get("instructions") is Array: return false
		if not r.get("attributes") is Dictionary or not r.get("model_version") is String: return false
		for attr in ATTRS:
			var v: Variant=r.attributes.get(attr)
			if not (v is float or v is int) or not is_finite(float(v)) or v<0 or v>100: return false
		for line in r.instructions:
			if not line is String: return false
		for row in r.ingredients:
			if not row is Dictionary: return false
			for key in ["sku_id","name","unit","inventory_unit"]:
				if not row.get(key) is String: return false
			for key in ["amount","inventory_amount"]:
				var v: Variant=row.get(key)
				if not (v is float or v is int) or not is_finite(float(v)) or v<=0 or v>2000: return false
	for drink in value.saved_drinks:
		if not drink is String or not value.saved_drinks[drink] is String or (not value.recipes.has(value.saved_drinks[drink]) and not value.get("archived",{}).has(value.saved_drinks[drink])): return false
		if not value.recipes.has(value.saved_drinks[drink]): continue
		# A revision may come from a later trial; each original cup keeps its own saved receipt.
		if value.recipes[value.saved_drinks[drink]].drink_id!=drink:
			var recorded:=false
			for old in value.get("versions",{}).get(value.saved_drinks[drink],[]):
				if old.drink_id==drink: recorded=true
			if not recorded: return false
	for key in ["acquired", "mastered"]:
		for id in value[key]:
			if not id is String or not value[key][id] is String: return false
	return true

static func blank_recipe() -> Dictionary:
	return {"id":"research_blank","version":1,"name":"自由 DIY","english_name":"FREE EXPLORATION","source_kind":"research_diy","ingredients":{},"ingredient_rows":[],"display_steps":[],"ice":[]}

static func sensory_snapshot() -> Dictionary:
	return Sensory.snapshot()

static func valid_model(model: Variant) -> bool:
	if Sensory.valid_model(model): return true
	if not model is Dictionary or model.get("version") not in ["research-sensory-1","research-sensory-2"] or not model.get("profiles") is Dictionary: return false
	for id in model.profiles:
		var p: Variant=model.profiles[id]
		if not id is String or not p is Array or p.size()!=4: return false
		for v in p:
			if not (v is float or v is int) or not is_finite(float(v)) or v<0 or v>100: return false
	return true

static func attributes(session: Dictionary, definitions: Dictionary) -> Dictionary:
	var serving: Dictionary=session.vessels.glass
	var model: Dictionary=session.get("sensory_model",sensory_snapshot())
	if Sensory.valid_model(model):
		return Sensory.evaluate(serving.contents,serving.get("solids",{}),definitions,model)
	# Frozen research-sensory-1 sessions retain their original calculations.
	var values: Array=[0.0,0.0,0.0,0.0]
	var volume:=0.0
	var missing: Array=[]
	for id in serving.contents:
		var ml:=float(serving.contents[id])
		volume+=ml
		var sku:=str(definitions.get(id,{}).get("sku_id",id))
		if not model.profiles.has(sku):
			missing.append(sku)
			continue
		for i in range(4): values[i]+=ml*float(model.profiles[sku][i])
	var result: Dictionary={}
	for i in range(4):
		var value:=clampf(values[i]/maxf(volume,.001),0,100)
		result[ATTRS[i]]=roundi(value) if model.version=="research-sensory-1" else value
	# Coarse playtest sugar contribution only. No fabricated melting or ABV.
	var sugar:=float(serving.get("solids",{}).get("sku_white_cane_sugar",0))
	result.sweetness=minf(100,float(result.sweetness)+100*sugar/maxf(20,volume))
	if model.version=="research-sensory-1": result.sweetness=roundi(result.sweetness)
	return {"attributes":result,"missing":missing,"version":model.version}

static func trial(session: Dictionary, definitions: Dictionary) -> Dictionary:
	var sensory:=attributes(session,definitions)
	var tags: Array=[]
	var labels: Array=["酒感明显","甜味突出","酸味突出","苦味突出"]
	for i in range(4):
		if sensory.attributes[ATTRS[i]]>=40: tags.append({"text":labels[i],"color":"ad8b57"})
	if session.vessels.glass.get("layers",[]).size()>1: tags.append({"text":"层次分明","color":"7f9c83"})
	if tags.is_empty(): tags.append({"text":"轻柔的","color":"7f9c83"})
	return {"version":sensory.version,"draft":true,"tier":"trial","title":"试调完成","color":"78a99b","score":null,"attributes":sensory.attributes,"targets":sensory.attributes.duplicate(),"has_target":false,"tags":tags,"reasons":["属性按实际成品计算；自由试调没有经典配方还原分。","可将成品用量整理成配方，再填写你的复做笔记。"],"notes":["感官试玩模型；不是真实 ABV。未模拟温度、融水、香气萃取。","感官描述不等于已获得配方 Buff。"],"subscores":{"recipe":0,"process":0,"finish":0},"trace":{},"recipe_version":session.recipe.version,"data_complete":sensory.get("data_complete",sensory.missing.is_empty()),"missing_profiles":sensory.missing}

static func legendary(id: String) -> Dictionary:
	for r in config().legendary_recipes:
		if r.get("id")==id: return r.duplicate(true)
	return {}

# Canonical prediction uses exactly the same units and model as actual production.
static func standard(recipe: Dictionary, model: Dictionary={}) -> Dictionary:
	if model.is_empty(): model=sensory_snapshot()
	if Sensory.valid_model(model): return Sensory.standard(recipe,model)
	var contents: Dictionary={}
	var solids: Dictionary={}
	var missing: Array=[]
	var rows: Array=recipe.get("ingredient_rows",[]) if recipe.get("ingredients") is Dictionary else recipe.get("ingredients",[])
	for row in rows:
		if row.get("use")=="装饰" or str(row.get("sku_id","")).begins_with("sku_ice_"): continue
		var quantity: Variant=row.get("inventory_amount")
		if row.get("inventory_unit")=="ml":
			if quantity==null: missing.append(row.sku_id)
			else: contents[row.sku_id]=float(contents.get(row.sku_id,0))+float(quantity)
		elif row.get("sku_id")=="sku_white_cane_sugar": solids[row.sku_id]=float(quantity)
	var sample:={"vessels":{"glass":{"contents":contents,"solids":solids}},"sensory_model":model}
	var result:=attributes(sample,{})
	result.missing.append_array(missing)
	return result
static func acquire_owned_recipes(research: Dictionary) -> bool:
	var updated := false
	for recipe: Dictionary in config().get("legendary_recipes", []):
		var item: Dictionary = research.get("story_items", {}).get(recipe.get("source_item_id", ""), {})
		var match_record: Dictionary = research.get("memory_matches", {}).get(item.get("awarded_by", ""), {})
		if item.get("owned", false) and match_record.get("outcome") == "win" and match_record.get("mode") == "story" and not research.acquired.has(recipe.id):
			research.acquired[recipe.id] = str(item.awarded_by)
			updated = true
	return updated

static func valid_image(value: Variant, require_file := false) -> bool:
	if not value is Dictionary or not value.get("path") is String or not value.get("source_drink_id") is String or not value.get("task_id") is String: return false
	var path: String=value.path
	if not path.begins_with("user://diy_cocktails/images/") or ".." in path or not path.ends_with(".png"): return false
	return not require_file or (value.get("confirmed",false) and FileAccess.file_exists(path) and Image.load_from_file(path) != null)

static func preview_result(recipe: Dictionary) -> Dictionary:
	if recipe.has("result"): return recipe.result.duplicate(true)
	var liquids: Dictionary={}
	var garnishes: Array=[]
	for row: Dictionary in recipe.get("ingredients",[]):
		if row.get("inventory_unit")=="ml": liquids[row.sku_id]=row.inventory_amount
		elif row.get("use")=="装饰":
			for i in range(int(row.get("inventory_amount",1))): garnishes.append(row.sku_id)
	var cup: String={"高球杯":"highball","古典杯":"rocks","碟形杯":"coupe","马天尼杯":"martini"}.get(recipe.get("glass","高球杯"),"highball")
	var ice_mass:=0.0
	for row: Dictionary in recipe.get("ice",[]):
		if row.get("use")=="出品冰": ice_mass+=float(row.get("amount",0))
	var batches: Array=[]
	if ice_mass>0: batches.append({"kind":"cube","volume":ice_mass,"mass_g":ice_mass,"pieces":maxi(1,roundi(ice_mass/12.5))})
	return {"image_path":recipe.get("image_path",""),"cup":cup,"capacity_ml":WorkbenchSession.CUP_CAPACITIES.get(cup,350),"contents":{"contents":liquids,"ice":"cube" if ice_mass>0 else "none","ice_batches":batches,"garnishes":garnishes}}
