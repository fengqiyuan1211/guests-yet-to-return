extends Node
const Muddle=preload("res://scripts/workbench_muddle.gd")
const LiquidState=preload("res://scripts/workbench_liquid_state.gd")
const LiquidAppearance=preload("res://scripts/workbench_liquid_appearance.gd")
## Production actions and warehouse stock commit together through Supplies.
## No sale or guest settlement is performed here.
signal changed
const Evaluation=preload("res://scripts/workbench_evaluation.gd")
const Research=preload("res://scripts/research_data.gd")
const Sensory=preload("res://scripts/sensory_model.gd")
const RECIPE := {"id": "workbench_practice", "version": 1, "name": "码头试作", "english_name": "Dockside Practice", "practice_only": true, "ingredients": {"gin": 30, "lime": 20, "syrup": 10}}
var MATERIALS := {
	"gin": {"name": "金酒", "en": "GIN", "sku_id": "sku_gin_london_dry"},
	"rum": {"name":"朗姆酒","en":"RUM","sku_id":"sku_white_rum"},
	"vodka": {"name":"伏特加","en":"VODKA","sku_id":"sku_vodka"},
	"lime": {"name": "青柠汁", "en": "LIME", "sku_id": "sku_lime_juice"},
	"syrup": {"name": "糖浆", "en": "SYRUP", "sku_id": "sku_simple_syrup"},
	"soda": {"name": "苏打水", "en": "SODA", "sku_id": "sku_soda_water"}
}
var GARNISHES := {"garnish":{"name":"青柠角","sku_id":"sku_lime_wedge","unit":"块"}, "lemon_slice":{"name":"柠檬片","sku_id":"sku_lemon_slice","unit":"片"}}
var SOLIDS: Dictionary = {}
const ITEM_ALIASES := {"sku_gin_london_dry":"gin","sku_white_rum":"rum","sku_vodka":"vodka","sku_lime_juice":"lime","sku_simple_syrup":"syrup","sku_soda_water":"soda","sku_lime_wedge":"garnish","sku_lemon_slice":"lemon_slice","tool_shaker":"shaker","tool_jigger":"jigger","tool_strainer":"strainer","tool_muddler":"muddler","tool_bar_spoon":"spoon","tool_mixing_glass":"mixing","glass_saucer_glass":"coupe","glass_highball_glass":"highball"}
const CUPS := ["rocks","coupe","highball","glass_cocktail_glass","glass_balloon_glass"]
const CAPACITIES := {"jigger": 90, "shaker": 500, "mixing": 500, "glass": 300}
# Playtest capacities, configurable independently of standard cocktail recipes.
const CUP_CAPACITIES := {"coupe":120, "glass_cocktail_glass":120, "highball":350, "rocks":350, "glass_balloon_glass":400}
const MAX_GARNISHES := 8
# Playtest portions: four 12.5 g cubes or one 50 g scoop. Ice is supplied by the ice station.
const ICE_PORTION_G := 50.0

func capacity(session: Dictionary, vessel: String) -> float:
	var saved:=float(session.get("vessel_capacities",CAPACITIES).get(vessel,CAPACITIES.get(vessel,300)))
	if vessel=="glass" and session.get("status")=="mixing":
		return maxf(saved,float(CUP_CAPACITIES.get(session.get("cup","coupe"),saved)))
	return saved

func ice_batches(vessel: Dictionary) -> Array:
	if vessel.has("ice_batches"): return vessel.ice_batches.duplicate(true)
	return [] if vessel.get("ice","none")=="none" else [{"kind":vessel.ice,"volume":40.0}]

func ice_volume(vessel: Dictionary) -> float:
	var total:=0.0
	for batch in ice_batches(vessel): total+=float(batch.volume)
	return total

func ice_mass(vessel: Dictionary) -> float:
	var total:=0.0
	for batch in ice_batches(vessel): total+=float(batch.get("mass_g",batch.volume))
	return total

func garnishes(vessel: Dictionary) -> Array:
	if vessel.has("garnishes"): return vessel.garnishes.duplicate()
	return [vessel.get("garnish_id","garnish")] if vessel.get("garnish",false) else []

func recommended_cup(recipe: Dictionary) -> String:
	var glass:=str(recipe.get("glass",""))
	if glass.contains("高球"): return "highball"
	if glass.contains("球形"): return "glass_balloon_glass"
	if glass.contains("鸡尾酒"): return "glass_cocktail_glass"
	return "coupe"

func set_cup(session: Dictionary, cup: String) -> void:
	session.cup=cup
	if not session.has("vessel_capacities"): session.vessel_capacities=CAPACITIES.duplicate()
	session.vessel_capacities.glass=CUP_CAPACITIES[cup]

var save_path := "user://workbench_practice.json"
var state: Dictionary = {}
var last_error := ""
var writable := true

func _ready() -> void:
	_load_catalog()
	for prefix in ["--slot-wallet=", "--dialogue-save=", "--game-save=", "--workbench-save="]:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with(prefix):
				save_path = arg.trim_prefix(prefix) + ("" if prefix == "--workbench-save=" else ".workbench")
	load_state()
	Supplies.changed.connect(_warehouse_changed)

func _load_catalog() -> void:
	for item: Dictionary in Supplies.catalog.list_items():
		if item.kind!="ingredient": continue
		var id: String=ITEM_ALIASES.get(item.id,item.id)
		var definition: Dictionary={"name":item.name,"sku_id":item.id,"unit":item.get("quantity_unit","件") if item.storage_mode=="quantity" else item.measurement_unit}
		if item.measurement_unit=="ml":
			if MATERIALS.has(id): definition.name=MATERIALS[id].name
			MATERIALS[id]=definition
		elif item.category=="装饰品": GARNISHES[id]=definition
		else: SOLIDS[id]=definition

func pantry_items(tab: String) -> Array:
	var result: Array=[]
	var group: String={"基酒":"原酒","配料":"配料","装饰":"装饰品","杯子":"杯型","器具":"器材"}.get(tab,"")
	if tab=="冰块": return [["cube","方冰 · 50 g / 4块"],["crushed","碎冰 · 50 g / 铲"]]
	for item: Dictionary in Supplies.catalog.list_items(group):
		if Supplies.total_remaining(item.id)<=0: continue
		result.append([str(ITEM_ALIASES.get(item.id,item.id)),str(item.name)])
	return result

func _fresh() -> Dictionary:
	return {"schema":2,"table_materials":[],"serial":0,"session":{},"receipts":{},"history":[],"research":Research.fresh()}

func research_state() -> Dictionary:
	return state.get("research",Research.fresh()).duplicate(true)

func is_research(session: Dictionary) -> bool:
	return session.get("mode","") in ["research_diy","research_legendary"]

func research_recipes() -> Array:
	var records: Array=research_state().recipes.values()
	records.sort_custom(func(a: Dictionary,b: Dictionary): return int(str(a.id).trim_prefix("diy_"))<int(str(b.id).trim_prefix("diy_")))
	return records

func research_note(session: Dictionary) -> String:
	var rows: Array[String]=["[b]本杯制作笔记[/b]", "实际取料 / 已进入成品"]
	var glass: Dictionary=session.vessels.glass
	for sku in session.get("consumed",{}):
		var definition: Dictionary=Supplies.get_item(str(sku))
		var material: String=ITEM_ALIASES.get(sku,sku)
		var served:=float(glass.contents.get(material,glass.get("solids",{}).get(material,0)))
		for garnish in garnishes(glass):
			if garnish==material: served+=1
		var unit:=str(definition.get("quantity_unit","份")) if definition.get("storage_mode")=="quantity" else str(definition.get("measurement_unit","份"))
		rows.append("%s：%s / %s %s" % [str(definition.get("name",sku)).replace("[","[lb]"),format_amount(float(session.consumed[sku])),format_amount(served),unit])
	if session.get("consumed",{}).is_empty(): rows.append("从右侧取料开始，配方由你创造。")
	rows.append("\n成品冰量 %s g\n属性在结束试调后揭晓。" % format_amount(ice_mass(glass)))
	var techniques: Dictionary={}
	for action in session.actions:
		if action.kind in ["shake","stir","muddle"]: techniques[action.kind]=float(techniques.get(action.kind,0))+float(action.payload.seconds)
	for kind in techniques: rows.append("%s %.1f 秒" % [{"shake":"摇和","stir":"搅拌","muddle":"轻压"}[kind],techniques[kind]])
	var base: Dictionary=session.get("base_recipe",{})
	if not base.is_empty():
		rows.append("\n[b]改编起点（仅供参考）[/b]\n"+str(base.name).replace("[","[lb]"))
		for row in base.get("ingredients",[]): rows.append("%s %s %s" % [str(row.name).replace("[","[lb]"),format_amount(float(row.amount)),row.unit])
	return "\n".join(rows)

func remaining(material: String) -> float:
	var definition: Dictionary=MATERIALS.get(material,GARNISHES.get(material,SOLIDS.get(material,{})))
	return Supplies.total_remaining(str(definition.get("sku_id","")))

func _warehouse_changed() -> void:
	if not Supplies.writable: return
	if not writable and not Supplies.workbench.is_empty(): return
	writable=true
	state=Supplies.workbench.duplicate(true) if not Supplies.workbench.is_empty() else _fresh()
	_refresh_stock_view()
	changed.emit()

func _refresh_stock_view() -> void:
	# Compatibility/read-only projection; never persist a second stock ledger.
	state.stock={}
	for material in MATERIALS: state.stock[material]=remaining(material)
	state.garnish_stock=remaining("garnish")

func _session(serial: int) -> Dictionary:
	var vessels := {}
	for id in CAPACITIES:
		vessels[id] = {"contents": {}, "layers":[], "ice": "none", "garnish": false,"ice_batches":[],"garnishes":[]}
	var capacities:=CAPACITIES.duplicate()
	capacities.glass=CUP_CAPACITIES.coupe
	return {"sensory_model":Sensory.snapshot(),"quality_model":Evaluation.config().duplicate(true),"liquid_profiles":LiquidAppearance.profiles(),"liquid_model":LiquidState.config(),"id": "practice-%d" % serial, "mode": "workbench", "status": "mixing", "recipe": RECIPE.duplicate(true), "vessels": vessels, "lid": false, "cup": "coupe", "vessel_capacities":capacities, "spoon_vessel":"", "actions": [], "withdrawn": {}, "consumed": {}, "result": {}}

func snapshot() -> Dictionary:
	return state.duplicate(true)

func amount(vessel: Dictionary) -> float:
	var total := 0.0
	for value in vessel.contents.values():
		total += float(value)
	return total

func _number(value: Variant, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= maximum

func _valid(data: Variant) -> bool:
	if not data is Dictionary or (data.get("schema") != 1 and data.get("schema") != 2):
		return false
	if not _valid_table_materials(data.get("table_materials", [])):
		return false
	for key in ["receipts", "session"]:
		if not data.get(key) is Dictionary:
			return false
	if not data.get("history") is Array or not _number(data.get("serial"), 1000000000):
		return false
	if data.has("research"):
		if not Research.valid(data.research): return false
		for record in data.research.recipes.values():
			if not _valid_vessel(record.result.get("contents"),1000) or not Evaluation.valid(record.result.get("evaluation",{})): return false
			if record.result.has("draft") and not valid_draft(record.result.draft): return false
	if data.schema==1:
		if not data.get("stock") is Dictionary or not _number(data.get("garnish_stock"),20): return false
		for id in ["gin","rum","vodka","lime","syrup","soda"]:
			if not _number(data.stock.get(id),600): return false
	for id in data.receipts:
		if not id is String or not data.receipts[id] is String:
			return false
	for archived in data.history:
		if not _valid_session(archived):
			return false
	return _valid_session(data.session)

func _valid_table_materials(value: Variant) -> bool:
	if not value is Array or value.size() > 5:
		return false
	var seen := {}
	for id in value:
		if not id is String or not MATERIALS.has(id) or seen.has(id): return false
		seen[id] = true
	return true

## Table slots are presentation state; replacing a bottle never consumes or refunds stock.
func place_table_material(id: String) -> bool:
	if not writable: return _error("存档不可写，请先恢复存档。")
	if state.get("session",{}).get("status")!="mixing": return _error("请先开始制作。")
	if not MATERIALS.has(id) or remaining(id)<.1: return _error("这款原料不足，请先补货。")
	var materials: Array=state.get("table_materials",[]).duplicate()
	if materials.has(id): return true
	if materials.size()==5: materials.pop_front()
	materials.append(id)
	return set_table_materials(materials)

func set_table_materials(materials: Array) -> bool:
	if not writable or not _valid_table_materials(materials):
		return _error("桌上最多摆放五款不同材料，请先拖回一款。")
	if state.get("table_materials", []) == materials: return true
	var next := state.duplicate(true)
	next.table_materials = materials.duplicate()
	return _commit(next)

func _valid_session(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var s: Dictionary = value
	if s.is_empty():
		return true
	if not s.get("id") is String or s.get("mode") not in ["practice","workbench","research_diy","research_legendary"] or s.get("status") not in ["mixing", "finished", "discarded"]:
		return false
	if not s.get("guest",{}) is Dictionary: return false
	if s.has("base_recipe"):
		var base: Variant=s.base_recipe
		if not base is Dictionary or not base.get("id") is String or not base.get("name") is String or not base.get("ingredients") is Array: return false
		if not (base.get("version") is String or Research.whole(base.get("version"))): return false
		for row in base.ingredients:
			if not row is Dictionary or not row.get("name") is String or not row.get("unit") is String or not _number(row.get("amount"),2000): return false
		if base.has("ice"):
			if not base.ice is Array: return false
			for row in base.ice:
				if not row is Dictionary or not row.get("name") is String or not row.get("unit") is String or not _number(row.get("amount"),2000): return false
	if is_research(s):
		if not s.get("inspiration_charged") is bool or not Research.valid_model(s.get("sensory_model")): return false
		if not _number(s.get("inspiration_cost"),1000) or not s.get("guest",{}).is_empty(): return false
		if s.has("quality_model") and (not s.quality_model is Dictionary or not s.quality_model.get("rules") is Dictionary or not s.quality_model.get("tiers") is Array): return false
	if s.has("sensory_model") and not Research.valid_model(s.sensory_model): return false
	if s.has("quality_model") and (not s.quality_model is Dictionary or not s.quality_model.get("rules") is Dictionary or not s.quality_model.get("tiers") is Array): return false
	if s.has("draft") and not valid_draft(s.draft): return false
	if not s.get("recipe") is Dictionary or not s.get("actions") is Array or not s.get("result") is Dictionary or not s.get("withdrawn") is Dictionary or not s.get("lid") is bool or s.get("cup") not in CUPS:
		return false
	if s.has("liquid_profiles") and not LiquidAppearance.valid_snapshot(s.liquid_profiles): return false
	if s.has("liquid_model") and not LiquidState.valid_model(s.liquid_model): return false
	if s.result.has("liquid_profiles") and not LiquidAppearance.valid_snapshot(s.result.liquid_profiles): return false
	if s.result.has("liquid_model") and not LiquidState.valid_model(s.result.liquid_model): return false
	if s.result.has("sensory_model") and not Research.valid_model(s.result.sensory_model): return false
	if not s.recipe.get("name") is String or not s.recipe.get("english_name") is String or not s.recipe.get("ingredients") is Dictionary or not _valid_recipe_snapshot(s.recipe):
		return false
	for material in s.recipe.ingredients:
		if not MATERIALS.has(material) or not _number(s.recipe.ingredients[material],2000):
			return false
	if s.has("vessel_capacities"):
		if not s.vessel_capacities is Dictionary: return false
		for id in CAPACITIES:
			if not _number(s.vessel_capacities.get(id),1000) or s.vessel_capacities[id]<=0: return false
	if s.get("spoon_vessel","") not in ["","mixing","glass","shaker"]: return false
	if s.get("spoon_vessel","")=="shaker" and s.lid: return false
	if not s.get("consumed",{}) is Dictionary: return false
	for sku in s.get("consumed",{}):
		if Supplies.get_item(str(sku)).get("kind")!="ingredient" or not _number(s.consumed[sku],2000): return false
	for action in s.actions:
		if not action is Dictionary or not action.get("command_id") is String or not action.get("kind") is String or not action.get("payload") is Dictionary:
			return false
		if action.kind not in ["withdraw","transfer","filter","ice","lid","cup","shake","stir","muddle","garnish","add_solid","spoon","empty","finish","discard"]:
			return false
		if action.has("liquid_model") and not LiquidState.valid_model(action.liquid_model): return false
		if action.kind == "withdraw" and (not MATERIALS.has(action.payload.get("material")) or not _number(action.payload.get("ml"),1000) or not CAPACITIES.has(action.payload.get("vessel","jigger"))):
			return false
		if action.kind in ["transfer","filter"] and (not CAPACITIES.has(action.payload.get("source")) or not CAPACITIES.has(action.payload.get("vessel"))):
			return false
		if action.kind=="empty" and (not CAPACITIES.has(action.payload.get("vessel")) or not _valid_vessel(action.get("removed"),1000)): return false
		if action.has("pour"):
			if action.kind not in ["transfer","filter"] or not action.pour is Dictionary: return false
			if not _number(action.pour.get("ml"),1000) or not _number(action.pour.get("fraction"),1) or not _number(action.pour.get("ice_g"),1000) or not action.pour.get("source_ice_left") is bool or not action.pour.get("solids") is Dictionary: return false
		if action.has("actual_ml") and (action.kind!="withdraw" or not _number(action.actual_ml,1000) or action.actual_ml<=0 or action.actual_ml>action.payload.ml): return false
		if action.payload.has("control") and not _number(action.payload.control,1): return false
		if action.payload.has("pressure") and not _number(action.payload.pressure,1): return false
		if action.has("transfers_ice") and (action.kind!="transfer" or not action.transfers_ice is bool): return false
		if action.has("mass_g") and (action.kind!="ice" or not _number(action.mass_g,ICE_PORTION_G) or action.mass_g<=0): return false
		if action.kind=="spoon" and action.payload.get("target","") not in ["","mixing","glass","shaker"]: return false
		if action.kind in ["shake","stir","muddle"] and not _number(action.payload.get("seconds"),.5):
			return false
	if not s.get("vessels") is Dictionary:
		return false
	var retained := {}
	if not s.get("waste",{}) is Dictionary: return false
	for material in s.get("waste",{}):
		if not MATERIALS.has(material) or not _number(s.waste[material],2000): return false
		retained[material]=float(s.waste[material])
	for id in CAPACITIES:
		var v: Variant = s.vessels.get(id)
		if not _valid_vessel(v,int(capacity(s,id))): return false
		for material in v.contents:
			retained[material]=float(retained.get(material,0))+float(v.contents[material])
	for material in s.withdrawn:
		if not MATERIALS.has(material) or not _number(s.withdrawn[material],2000) or not is_equal_approx(float(s.withdrawn[material]),float(retained.get(material,0))):
			return false
	for material in retained:
		if not s.withdrawn.has(material):
			return false
	if s.status == "finished":
		if s.result.has("evaluation") and not Evaluation.valid(s.result.evaluation): return false
		if s.result.has("draft") and not valid_draft(s.result.draft): return false
		if not _valid_vessel(s.result.get("contents"),int(capacity(s,"glass"))) or not s.result.get("waste") is Dictionary or not s.result.get("drink_id") is String:
			return false
		for material in s.result.waste:
			if not MATERIALS.has(material) or not _number(s.result.waste[material],2000):
				return false
	return true

func recipe_snapshot(reference: Dictionary) -> Dictionary:
	var result := reference.duplicate(true)
	result.ingredient_rows = reference.get("ingredients",[]).duplicate(true)
	result.ingredients = {}
	for row in result.ingredient_rows:
		var material: String = ITEM_ALIASES.get(row.get("sku_id",""),row.get("sku_id",""))
		var quantity: Variant = row.get("inventory_amount")
		if MATERIALS.has(material) and row.get("inventory_unit")=="ml" and _number(quantity,2000) and quantity>0:
			result.ingredients[material] = float(result.ingredients.get(material,0))+float(quantity)
	result.practice_only = false
	result.source_kind = "menu_catalog"
	if reference.get("unlock_kind") == "legendary_mastery": result.source_kind = "research_legendary"
	# Content hash is a revision identifier when the catalog has no numbered version.
	result.version = reference.get("version", JSON.stringify(reference).sha256_text())
	# Normalize numeric types to the same JSON representation used by saved cups.
	return JSON.parse_string(JSON.stringify(result))

func _valid_recipe_snapshot(recipe: Dictionary) -> bool:
	if recipe.get("practice_only")==true: return true
	if recipe.get("source_kind") not in ["menu_catalog","research_diy","research_legendary"] or not recipe.get("id") is String or not recipe.get("ingredient_rows") is Array: return false
	if not recipe.get("version") is String and not recipe.get("version") is int and not recipe.get("version") is float: return false
	for row in recipe.ingredient_rows:
		if not row is Dictionary or not row.get("name") is String or not row.get("unit") is String or not row.get("sku_id") is String or not _number(row.get("amount"),2000): return false
	for field in ["display_steps","ice"]:
		if not recipe.get(field,[]) is Array: return false
	for step in recipe.get("display_steps",[]):
		if not step is Dictionary or not step.get("instruction") is String: return false
	for row in recipe.get("ice",[]):
		if not row is Dictionary or not row.get("name") is String or not row.get("unit") is String or not _number(row.get("amount"),2000): return false
	return true

func draft_definitions() -> Dictionary:
	var definitions:=MATERIALS.duplicate(true)
	definitions.merge(SOLIDS)
	definitions.merge(GARNISHES)
	definitions["ice:cube"]={"name":"标准方冰","unit":"g"}
	definitions["ice:crushed"]={"name":"碎冰","unit":"g"}
	return definitions

func valid_draft(value: Variant) -> bool:
	if not value is Dictionary or value.get("version")!=1 or not Research.whole(value.get("revision")) or not value.get("targets") is Dictionary: return false
	var definitions:=draft_definitions()
	for material in value.targets:
		if not material is String or not definitions.has(material) or not _number(value.targets[material],2000) or value.targets[material]<=0: return false
		if GARNISHES.has(material) and not Research.whole(value.targets[material],MAX_GARNISHES): return false
		if SOLIDS.has(material) and definitions[material].get("unit")!="g" and not Research.whole(value.targets[material],2000): return false
	return true

func draft_from_reference(base: Dictionary) -> Dictionary:
	var draft:={"version":1,"revision":0,"targets":{}}
	var definitions:=draft_definitions()
	for row in base.get("ingredients",[]):
		var material: String=ITEM_ALIASES.get(str(row.get("sku_id","")),str(row.get("sku_id","")))
		var quantity:=float(row.get("inventory_amount",row.get("amount",0)))
		if definitions.has(material) and quantity>0: draft.targets[material]=float(draft.targets.get(material,0))+quantity
	for row in base.get("ice",[]):
		if row.get("unit")=="g":
			var material:="ice:crushed" if "碎" in str(row.get("name","")) else "ice:cube"
			draft.targets[material]=float(draft.targets.get(material,0))+float(row.amount)
	return draft

# Count physical contents across the table once. Transfers do not consume the
# target twice; discarded liquid no longer occupies the planned quantity.
func draft_amounts(session: Dictionary) -> Dictionary:
	var amounts: Dictionary={}
	for vessel in session.get("vessels",{}).values():
		for key in ["contents","solids"]:
			for material in vessel.get(key,{}): amounts[material]=float(amounts.get(material,0))+float(vessel[key][material])
		for material in garnishes(vessel): amounts[material]=float(amounts.get(material,0))+1
		for batch in ice_batches(vessel):
			var material:="ice:"+str(batch.kind)
			amounts[material]=float(amounts.get(material,0))+float(batch.get("mass_g",batch.volume))
	return amounts

func dose_target(material: String, session: Dictionary) -> float:
	if session.get("mode")=="research_diy":
		var planned: Dictionary=session.get("draft",{}).get("targets",{})
		if not planned.has(material): return 30.0
		return minf(60.0,maxf(0,float(planned[material])-float(draft_amounts(session).get(material,0))))
	var targets: Dictionary=session.get("recipe",RECIPE).ingredients
	if not targets.has(material): return 30.0
	var required := float(targets[material])
	var remaining_target := required-float(session.get("withdrawn",{}).get(material,0))
	return minf(60.0, remaining_target if remaining_target>0 else required)

func format_amount(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")

func recipe_note(session: Dictionary) -> String:
	var recipe: Dictionary=session.get("recipe",RECIPE)
	var rows: Array[String]=[]
	if recipe.has("ingredient_rows"):
		for row in recipe.ingredient_rows:
			var sku := str(row.sku_id)
			var definition: Dictionary=Supplies.get_item(sku)
			var unit: String=str(row.unit)
			if unit in ["piece","sprig"]: unit=str(definition.get("quantity_unit", "份"))
			var used := float(session.get("consumed",{}).get(sku,0))
			var progress := " · 已取 %s" % format_amount(used)
			if row.get("inventory_amount")==null: progress=" · 换算待定"
			rows.append("%s %s %s%s" % [row.name,format_amount(float(row.amount)),unit,progress])
		for ice in recipe.get("ice",[]):
			var portion:=float(ice.amount)/ICE_PORTION_G
			var cube:=not str(ice.get("sku_id","")).contains("crushed")
			rows.append("%s %s g＝%s份%s\n%s" % [ice.name,format_amount(float(ice.amount)),format_amount(portion),"＝%s块" % format_amount(portion*4) if cube else "", "方冰1份4块，共50g（每块12.5g）" if cube else "碎冰1份1铲，共50g"])

		rows.append("\n杯型："+str(recipe.get("glass","自选")))
		for step in recipe.get("display_steps",[]): rows.append("%s. %s" % [str(step.get("number","")),step.instruction])
	else:
		for material in recipe.ingredients:
			rows.append("%s %s ml · 已取 %s" % [MATERIALS[material].name,format_amount(float(recipe.ingredients[material])),format_amount(float(session.get("withdrawn",{}).get(material,0)))])
		rows.append("\n量取 → 加冰 → 摇和 → 过滤")
	return "\n".join(rows)

func _valid_vessel(v: Variant, capacity: int) -> bool:
	if not v is Dictionary or not v.get("contents") is Dictionary or v.get("ice") not in ["none", "cube", "crushed"] or not v.get("garnish") is bool:
		return false
	if not LiquidState.valid(v) or not Muddle.valid(v): return false
	if not v.get("solids",{}) is Dictionary: return false
	for material in v.get("solids",{}):
		if not SOLIDS.has(material) or not _number(v.solids[material],2000): return false
	for material in v.contents:
		if not MATERIALS.has(material) or not _number(v.contents[material],capacity):
			return false
	if not v.get("ice_batches",[]) is Array or not v.get("garnishes",[]) is Array: return false
	if ice_batches(v).size()>20 or garnishes(v).size()>MAX_GARNISHES: return false
	for batch in ice_batches(v):
		if not batch is Dictionary or batch.get("kind") not in ["cube","crushed"] or not _number(batch.get("volume"),ICE_PORTION_G) or batch.volume<=0: return false
		if batch.has("pieces") and (not _number(batch.pieces,10) or batch.pieces<1 or batch.pieces!=floor(batch.pieces)): return false
		if batch.has("mass_g"):
			if not _number(batch.mass_g,ICE_PORTION_G) or not is_equal_approx(batch.mass_g,batch.volume): return false
		elif batch.volume!=40: return false # Legacy portions stay 40 ml / 40 g.
	for garnish in garnishes(v):
		if not GARNISHES.has(garnish): return false
	if v.ice!=("none" if ice_batches(v).is_empty() else ice_batches(v)[0].kind): return false
	if v.garnish!=not garnishes(v).is_empty(): return false
	return amount(v) + ice_volume(v) <= capacity+.00001

func load_state() -> bool:
	writable=Supplies.writable
	last_error=""
	if not writable:
		state=_fresh()
		_refresh_stock_view()
		return _error(Supplies.last_error)
	var data: Variant=Supplies.workbench.duplicate(true)
	if not Supplies.workbench_initialized and FileAccess.file_exists(save_path):
		data=JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if data is Dictionary and data.get("schema")==1 and data.get("stock") is Dictionary:
			for id in ["rum","vodka"]:
				if not data.stock.has(id): data.stock[id]=600
	if data is Dictionary and data.is_empty(): data=_fresh()
	if not _valid(data):
		state=_fresh()
		_refresh_stock_view()
		writable=false
		Supplies._protect("工作台记录无法读取，原库存及记录已保留。")
		return _error(Supplies.last_error)
	data.schema=2
	data.erase("stock")
	data.erase("garnish_stock")
	if not data.has("table_materials"): data.table_materials=[]
	# Repair the obsolete Gin & Tonic cup judgement, including saved results.
	var repaired:=_repair_gin_tonic_evaluations(data)
	if not data.has("research"): data.research=Research.fresh()
	repaired=Research.acquire_owned_recipes(data.research) or repaired
	# Preserve actual cups, recipes and inventory; only the derived evaluation changes.
	if repaired or not Supplies.workbench_initialized or Supplies.workbench.get("schema")!=2:
		if not Supplies.commit_workbench(data):
			writable=false
			state=data
			_refresh_stock_view()
			return _error(Supplies.last_error)
	state=data
	_refresh_stock_view()
	return true

func _commit(next: Dictionary, amounts: Dictionary={}) -> bool:
	var durable:=next.duplicate(true)
	durable.erase("stock")
	durable.erase("garnish_stock")
	if not Supplies.commit_workbench(durable,amounts): return _error(Supplies.last_error)
	state=durable
	_refresh_stock_view()
	last_error=""
	changed.emit()
	return true

func reset_game() -> bool:
	if not _commit(_fresh()):
		return false
	writable = true
	return true

func command(id: String, session_id: String, kind: String, payload: Dictionary = {}) -> bool:
	if not writable:
		return false
	if id.is_empty():
		last_error = "操作缺少编号。"
		return false
	var signature := JSON.stringify([session_id, kind, payload])
	if state.receipts.has(id):
		if state.receipts[id] == signature:
			last_error = ""
			return true
		last_error = "操作编号已经使用，请重新操作。"
		return false
	var next := state.duplicate(true)
	if not next.has("research"): next.research=Research.fresh()
	var consumption := {}
	var outcome: Dictionary={}
	var s: Dictionary = next.session
	if kind=="refresh_appearance":
		if s.get("id")!=session_id or s.get("status")!="mixing": return _error("只更新正在制作这一杯的液体配色。")
		s.liquid_profiles=LiquidAppearance.profiles()
	elif kind=="edit_draft":
		if s.get("id")!=session_id or s.get("mode")!="research_diy" or s.get("status")!="mixing": return _error("只能编辑正在试调的 DIY 草稿。")
		var draft: Dictionary=s.get("draft",{"version":1,"revision":0,"targets":{}}).duplicate(true)
		if payload.get("revision")!=draft.revision: return _error("草稿已经更新，请按最新用量重新编辑。")
		var material:=str(payload.get("material",""))
		if not draft_definitions().has(material): return _error("请选择可用的原料或冰型。")
		if payload.get("remove",false)==true: draft.targets.erase(material)
		else: draft.targets[material]=payload.get("amount")
		draft.revision+=1
		if not valid_draft(draft): return _error("用量应大于 0、不超过 2000；按块或枝计数的原料请填整数。")
		s.draft=draft
	elif kind=="record_memory_match":
		var rules := preload("res://scripts/stick_memory_rules.gd")
		if not rules.valid_result(payload): return _error("这一局还没打完，先不收酒谱。")
		if not next.research.has("memory_matches"): next.research.memory_matches={}
		var match_id := str(payload.match_id)
		if not next.research.memory_matches.has(match_id):
			if payload.get("mode") not in ["story", "practice"]: return _error("请选择练习，或从小线的邀请开始比赛。")
			if payload.mode == "story" and not CustomerService.can_award_memory(str(payload.get("visit_id", ""))): return _error("这次邀请已经结束，请返回酒馆。")
		if next.research.memory_matches.has(match_id):
			if next.research.memory_matches[match_id] != payload: return _error("这一局的比分不一致，请保留记录。")
		else: next.research.memory_matches[match_id]=payload.duplicate(true)
		if not next.research.has("story_items"): next.research.story_items={}
		if payload.outcome=="win" and payload.get("mode") == "story" and not next.research.story_items.has(rules.ITEM_ID):
			next.research.story_items[rules.ITEM_ID]={"owned":true,"unlocked":true,"quantity":1,"awarded_by":match_id}
		Research.acquire_owned_recipes(next.research)
	elif kind=="grant_legendary":
		var ref:=Research.legendary(str(payload.get("recipe_id","")))
		if ref.is_empty(): return _error("没有这份传说配方，等待剧情配方接入。")
		Research.acquire_owned_recipes(next.research)
		if not next.research.acquired.has(ref.id): return _error("请先从小线手中收下这份酒单。")
	elif kind=="save_legendary_image":
		if s.get("id")!=session_id or s.get("mode")!="research_legendary" or s.get("status")!="finished" or not s.result.get("research_success",false): return _error("请先完美研习这份传说酒单。")
		var picture: Dictionary=payload.get("image",{})
		if not Research.valid_image(picture,true) or picture.source_drink_id!=s.result.drink_id: return _error("酒图尚未生成，或不属于这一杯。")
		if not next.research.has("legendary_images"): next.research.legendary_images={}
		next.research.legendary_images[s.recipe.id]=picture.duplicate(true)
		s.result.image_path=picture.path
	elif kind=="save_research":
		if s.get("id")!=session_id or s.get("mode")!="research_diy" or s.get("status")!="finished": return _error("请先完成一杯 DIY 试调。")
		var drink: String=s.result.drink_id
		if next.research.saved_drinks.has(drink):
			next.receipts[id]=signature
			return _commit(next) # Keep the retry receipt without creating a second recipe.
		if not s.result.evaluation.get("data_complete",false): return _error("部分材料的感官数据未配置，暂不能保存配方。")
		var title:=str(payload.get("name","")).strip_edges()
		var english:=str(payload.get("english_name","")).strip_edges()
		var memo:=str(payload.get("notes","")).strip_edges()
		if title.is_empty() or title.length()>40 or english.length()>70 or memo.length()>500: return _error("请填写酒名（最多40字）；英文名最多70字，笔记最多500字。")
		var picture: Dictionary=payload.get("image",{})
		if not Research.valid_image(picture,true) or picture.source_drink_id!=drink: return _error("请先生成并确认这一杯的酒图，再保存成品。")
		s.result.image_path=picture.path
		next.research.serial+=1
		var recipe_id:="diy_%d" % int(next.research.serial)
		var record:=_research_record(s,recipe_id,title,english,memo)
		record.image_path=picture.path
		record.thumbnail=picture.path
		record.image_generation=picture.duplicate(true)
		record.story=str(payload.get("story",memo)).left(1000)
		next.research.recipes[recipe_id]=record
		next.research.saved_drinks[drink]=recipe_id
	elif kind=="begin_research":
		if not s.is_empty() and s.status=="mixing" and (not s.actions.is_empty() or not s.get("draft",{}).get("targets",{}).is_empty()): return _error("桌上还有草稿或半成品，请先继续制作，或在工作台明确丢弃。")
		var mode:=str(payload.get("mode","research_diy"))
		if mode not in ["research_diy","research_legendary"]: return _error("研发模式无效。")
		var recipe:=Research.blank_recipe()
		var base: Dictionary={}
		var base_id:=str(payload.get("base_recipe_id",""))
		if mode=="research_diy" and not base_id.is_empty():
			base=next.research.recipes.get(base_id,MenuCatalog.get_recipe(base_id)).duplicate(true)
			if base.is_empty() or not base.get("unlocked",false): return _error("这款基础配方尚未获得，请重新选择研发起点。")
			# Keep only a compact immutable reference, not another nested image/history tree.
			base={"id":base.id,"version":base.get("version",JSON.stringify(base).sha256_text()),"name":base.name,"ingredients":base.ingredients.duplicate(true),"ice":base.get("ice",[]).duplicate(true)}
		if mode=="research_legendary":
			var ref:=Research.legendary(str(payload.get("recipe_id","")))
			if ref.is_empty() or not next.research.acquired.has(ref.get("id","")): return _error("请先获得这份传说配方。")
			recipe=recipe_snapshot(ref)
			recipe.source_kind="research_legendary"
			if not recipe.get("quality_rule") is Dictionary or recipe.quality_rule.is_empty(): return _error("这份配方的研习标准尚未配置。")
		if not s.is_empty(): next.history.append(s.duplicate(true))
		next.serial+=1
		next.session=_session(int(next.serial))
		next.session.mode=mode
		next.session.guest={}
		next.session.recipe=recipe
		if not base.is_empty(): next.session.base_recipe=base
		if mode=="research_diy": next.session.draft=draft_from_reference(base)
		next.session.sensory_model=Research.sensory_snapshot()
		next.session.quality_model=Evaluation.config().duplicate(true)
		next.session.inspiration_charged=false
		next.session.inspiration_cost=int(Research.config().diy_cost) if mode=="research_diy" else 0
		set_cup(next.session,"highball" if mode=="research_diy" else recommended_cup(recipe))
		next.table_materials=[]
	elif kind == "select_recipe":
		var replacing: bool=not s.is_empty() and s.status=="mixing" and not s.actions.is_empty()
		if payload.has("replace_session_id") and str(payload.replace_session_id)!=str(s.get("id","")):
			return _error("桌上这一杯已变化，请重新选择后开工。")
		if replacing and not payload.has("replace_session_id"):
			return _error("桌上还有半成品，请选择继续，或在选酒页收拾并制作新酒。")
		var recipe_id := str(payload.get("recipe_id", ""))
		var listed := false
		for entry in MenuCatalog.entries:
			if entry.id == recipe_id: listed = true
		var reference: Dictionary = MenuCatalog.get_recipe(recipe_id)
		if not listed or reference.is_empty() or not reference.get("unlocked",false):
			return _error("这款酒已不在营业酒单中，请重新选择。")
		var recipe := recipe_snapshot(reference)
		if not _valid_recipe_snapshot(recipe): return _error("这款酒的配方资料暂时无法用于制作。")
		if not payload.get("guest",{}) is Dictionary: return _error("顾客信息无法读取。")
		if replacing:
			s.status="discarded"
			s.spoon_vessel=""
			s.result={"withdrawn":s.withdrawn.duplicate(true),"waste":s.withdrawn.duplicate(true),"consumed":s.get("consumed",{}).duplicate(true),"sales":false}
			s.actions.append({"command_id":id+"-discard","kind":"discard","payload":{"reason":"new_recipe"}})
		if not s.is_empty(): next.history.append(s.duplicate(true))
		next.table_materials=[]
		next.serial += 1
		next.session = _session(int(next.serial))
		next.session.recipe = recipe
		set_cup(next.session,recommended_cup(recipe))
		next.session.guest = payload.get("guest",{}).duplicate(true)
		# A customer order freezes the same sensory model for cup and settlement.
		# Restored old orders keep their original cup model for this reception.
		var visit_id:=str(next.session.guest.get("visit_id",""))
		var active: Dictionary=CustomerService.state.get("active",{})
		if not visit_id.is_empty() and visit_id==str(active.get("id","")):
			var frozen: Dictionary=active.get("rules_snapshot",{}).get("sensory",{})
			if Sensory.valid_model(frozen): next.session.sensory_model=frozen.duplicate(true)
			else: next.session.erase("sensory_model")
	elif kind == "start":
		if not s.is_empty() and s.status == "mixing":
			return _error("桌上还有半成品，请先继续或丢弃。")
		if not s.is_empty():
			next.history.append(s.duplicate(true))
		next.serial += 1
		next.session = _session(int(next.serial))
		next.table_materials=[]
		# Restarting the same drink keeps its frozen reference and reception context.
		if not s.is_empty():
			next.session.recipe = s.recipe.duplicate(true)
			set_cup(next.session,recommended_cup(s.recipe))
			next.session.guest = s.get("guest",{}).duplicate(true)
			if s.has("sensory_model"): next.session.sensory_model=s.sensory_model.duplicate(true)
			else: next.session.erase("sensory_model")
			if s.has("quality_model"): next.session.quality_model=s.quality_model.duplicate(true)
			if is_research(s):
				next.session.mode=s.mode
				next.session.sensory_model=s.sensory_model.duplicate(true)
				next.session.quality_model=s.get("quality_model",Evaluation.config()).duplicate(true)
				next.session.inspiration_charged=false
				next.session.inspiration_cost=s.inspiration_cost
				set_cup(next.session,s.cup)
				if s.has("base_recipe"): next.session.base_recipe=s.base_recipe.duplicate(true)
				if s.has("draft"): next.session.draft=s.draft.duplicate(true)
	else:
		if s.is_empty() or s.id != session_id or s.status != "mixing":
			return _error("这一杯已经结束或已被替换。")
		var vessel_id := str(payload.get("vessel", "jigger" if kind=="withdraw" else "glass"))
		if not s.vessels.has(vessel_id):
			return _error("请先选择桌上的容器。")
		if not s.has("vessel_capacities"): s.vessel_capacities=CAPACITIES.duplicate()
		s.vessel_capacities.glass=capacity(s,"glass")
		if not s.has("liquid_profiles"): s.liquid_profiles=LiquidAppearance.profiles()
		if not s.has("liquid_model"): s.liquid_model=LiquidState.config()
		for vessel in s.vessels.values(): LiquidState.ensure(vessel)
		var v: Dictionary = s.vessels[vessel_id]
		match kind:
			"withdraw":
				var material := str(payload.get("material", ""))
				var quantity: Variant = payload.get("ml")
				if not MATERIALS.has(material) or not _number(quantity, 1000) or quantity <= 0:
					return _error("取料量需要在 0–1000 ml 以内。")
				if vessel_id=="shaker" and s.lid:
					return _error("先打开摇壶盖，再加入材料。")
				quantity=minf(float(quantity),maxf(0,capacity(s,vessel_id)-amount(v)-ice_volume(v)))
				if quantity<.00001: return _error("容器已满，请先出杯或倒掉一些内容物。")
				outcome.actual_ml=float(quantity)
				outcome.liquid_layered=true
				if remaining(material) < quantity:
					return _error("%s库存不足（剩余 %s ml），请去商店补货。" % [MATERIALS[material].name,str(snappedf(remaining(material),.01))])
				consumption[MATERIALS[material].sku_id]=float(quantity)
				LiquidState.add(v,{material:float(quantity)})
				s.withdrawn[material] = float(s.withdrawn.get(material, 0)) + float(quantity)
			"add_solid":
				var material: String=str(payload.get("material",""))
				if not SOLIDS.has(material) or vessel_id=="jigger" or (vessel_id=="shaker" and s.lid): return _error("请把固体配料放入打开的制作容器。")
				if remaining(material)<1: return _error("配料不足，请去商店补货。")
				if float(s.get("consumed",{}).get(SOLIDS[material].sku_id,0))>=2000: return _error("容器中这份配料已达到上限。")
				if not v.has("solids"): v.solids={}
				v.solids[material]=float(v.solids.get(material,0))+1
				if material==Muddle.LEAF: Muddle.add(v)
				consumption[SOLIDS[material].sku_id]=1
			"transfer", "filter":
				var source_id := str(payload.get("source", "jigger"))
				if not s.vessels.has(source_id) or source_id == vessel_id:
					return _error("请选择另一个接酒容器。")
				var source: Dictionary = s.vessels[source_id]
				if amount(source) <= 0 and (kind=="filter" or (source.get("solids",{}).is_empty() and ice_batches(source).is_empty() and garnishes(source).is_empty())):
					return _error("源容器中还没有液体。")
				var built_in_filter: bool=kind=="filter" and source_id=="shaker" and vessel_id!="shaker" and payload.get("integrated_strainer")==true
				if (vessel_id == "shaker" or source_id == "shaker") and s.lid and not built_in_filter:
					return _error("先打开摇壶盖，再倒入或过滤。")
				if kind == "filter" and source_id not in ["shaker", "mixing"]:
					return _error("滤冰器用于摇壶或搅拌杯出酒。")
				var free:=maxf(0,capacity(s,vessel_id)-amount(v)-ice_volume(v))
				if free<.00001: return _error("接酒容器已满，余量保留在原容器；可拖到左下方倒掉。")
				outcome.pour=_pour_contents(source,v,free,kind=="filter")
				if float(outcome.pour.ml)<=.00001 and float(outcome.pour.ice_g)<=.00001 and outcome.pour.solids.is_empty() and int(outcome.pour.garnish_count)==0:
					return _error("剩余空间放不下冰块或配料，内容物保留在原容器。")
				if s.get("spoon_vessel","")==source_id: s.spoon_vessel=""
			"empty":
				if amount(v)<=0 and ice_batches(v).is_empty() and v.get("solids",{}).is_empty() and garnishes(v).is_empty(): return _error("这个容器已经空了。")
				outcome.removed=v.duplicate(true)
				if not s.has("waste"): s.waste={}
				for material in v.contents: s.waste[material]=float(s.waste.get(material,0))+float(v.contents[material])
				v.contents={}
				v.layers=[]
				v.solids={}
				v.mint_processing=[]
				v.ice_batches=[]
				v.ice="none"
				v.garnishes=[]
				v.garnish=false
				if s.get("spoon_vessel","")==vessel_id: s.spoon_vessel=""
				if vessel_id=="shaker": s.lid=false

			"ice":
				if vessel_id == "jigger" or (vessel_id == "shaker" and s.lid):
					return _error("请选打开的制作容器加冰。")
				if payload.get("ice") not in ["cube", "crushed"] or amount(v) + ice_volume(v) + ICE_PORTION_G > capacity(s,vessel_id):
					return _error("请选择冰型，并确认容器有空间。")
				v.ice_batches=ice_batches(v)
				v.ice_batches.append({"kind":payload.ice,"volume":ICE_PORTION_G,"mass_g":ICE_PORTION_G})
				v.ice = v.ice_batches[0].kind
			"spoon":
				var target:=str(payload.get("target",""))
				if target not in ["","mixing","glass","shaker"] or (target=="shaker" and s.lid):
					return _error("请将吧勺插入打开的杯子或容器。")
				s.spoon_vessel=target
			"lid":
				if not s.lid and s.get("spoon_vessel","")=="shaker": return _error("先点击露出的吧勺收回，再合上摇壶。")
				s.lid = not s.lid
			"cup":
				if payload.get("cup") not in CUPS:
					return _error("未知杯型。")
				if amount(s.vessels.glass)+ice_volume(s.vessels.glass)>CUP_CAPACITIES[payload.cup]:
					return _error("这只杯子装不下现有酒液和冰，请选更大的杯型。")
				set_cup(s,payload.cup)
			"shake", "stir", "muddle":
				if kind=="stir" and s.get("spoon_vessel","")!=vessel_id: return _error("先从器具菜单将吧勺拖入这个杯子。")
				if amount(v) == 0 and v.get("solids",{}).is_empty():
					return _error("先加入材料再操作。")
				if kind == "shake" and (vessel_id != "shaker" or not s.lid):
					return _error("请选摇壶并盖好盖子。")
				if kind != "shake" and (vessel_id not in ["glass", "mixing", "shaker"] or (vessel_id == "shaker" and s.lid)):
					return _error("请选打开的容器。")
				if payload.has("pressure") and not _number(payload.pressure,1): return _error("轻压力度数据无效。")
				if payload.has("control") and not _number(payload.control,1): return _error("动作节奏数据无效。")
				if not _number(payload.get("seconds"), 0.5) or payload.seconds <= 0:
					return _error("没有检测到有效动作。")
				if kind=="muddle": Muddle.press(v,float(payload.seconds),float(payload.get("pressure",.4)))
				if kind in ["stir","shake"]:
					LiquidState.mix(v,float(payload.seconds),kind,float(payload.get("control",1)),s.liquid_model)
					outcome.liquid_model=s.liquid_model.duplicate(true)
			"garnish":
				if amount(s.vessels.glass) == 0 or garnishes(s.vessels.glass).size()>=MAX_GARNISHES:
					return _error("先加入酒液；杯沿最多摆放 %d 份装饰。" % MAX_GARNISHES)
				var garnish: String=str(payload.get("material","garnish"))
				if not GARNISHES.has(garnish): return _error("请选择有效装饰。")
				if remaining(garnish)<1: return _error(GARNISHES[garnish].name+"库存不足，请去商店补货。")
				s.vessels.glass.garnishes=garnishes(s.vessels.glass)
				s.vessels.glass.garnishes.append(garnish)
				s.vessels.glass.garnish = true
				s.vessels.glass.garnish_id=garnish
				consumption[GARNISHES[garnish].sku_id]=1
			"finish":
				if amount(s.vessels.glass) == 0:
					return _error("请先将酒液倒入成品杯。")
				s.status = "finished"
				s.spoon_vessel=""
				var waste: Dictionary=s.get("waste",{}).duplicate(true)
				for source_id in s.vessels:
					if source_id != "glass":
						for material in s.vessels[source_id].contents:
							waste[material] = float(waste.get(material, 0)) + float(s.vessels[source_id].contents[material])
				var definitions:=MATERIALS.duplicate(true)
				definitions.merge(SOLIDS)
				definitions.merge(GARNISHES)
				var evaluation:=Evaluation.evaluate(s,definitions)
				s.result = {"liquid_profiles":s.liquid_profiles.duplicate(true),"liquid_model":s.liquid_model.duplicate(true),"evaluation":evaluation,"drink_id": s.id + "-drink", "guest":s.get("guest",{}).duplicate(true), "recipe": s.recipe.duplicate(true), "contents": s.vessels.glass.duplicate(true), "cup":s.cup,"capacity_ml":capacity(s,"glass"), "withdrawn": s.withdrawn.duplicate(true), "waste": waste, "actions": s.actions.duplicate(true), "consumed":s.get("consumed",{}).duplicate(true), "sales": false}
				if s.has("sensory_model"): s.result.sensory_model=s.sensory_model.duplicate(true)
				if s.has("draft"): s.result.draft=s.draft.duplicate(true)
				if s.recipe.get("id") == "childhood_keepsake" and s.recipe.get("source_kind") == "research_legendary" and s.result.evaluation.get("tier") == "perfect":
					s.result["legendary_buff"] = s.recipe.get("buff", {}).duplicate(true)
				if s.mode=="research_legendary":
					if not next.research.acquired.has(s.recipe.id): return _error("未找到这份传说配方的获得记录，请保留试调并检查存档。")
					s.result.research_success=evaluation.tier=="perfect"
					if s.result.research_success and not next.research.mastered.has(s.recipe.id): next.research.mastered[s.recipe.id]=s.result.drink_id
			"discard":
				s.status = "discarded"
				s.spoon_vessel=""
				s.result = {"withdrawn": s.withdrawn.duplicate(true), "waste": s.withdrawn.duplicate(true), "consumed":s.get("consumed",{}).duplicate(true), "sales": false}
			_:
				return _error("未知操作。")
		if s.get("mode")=="research_diy" and not consumption.is_empty() and not s.inspiration_charged:
			if next.research.inspiration<s.inspiration_cost: return _error("灵感不足，无法开始新的 DIY 试调。")
			next.research.inspiration-=s.inspiration_cost
			s.inspiration_charged=true
		if not s.has("consumed"): s.consumed={}
		for sku in consumption: s.consumed[sku]=float(s.consumed.get(sku,0))+float(consumption[sku])
		var action:={"command_id": id, "kind": kind, "payload": payload.duplicate(true)}
		action.merge(outcome)
		if kind=="ice": action.mass_g=ICE_PORTION_G
		if kind=="transfer": action.transfers_ice=true
		s.actions.append(action)
	next.receipts[id] = signature
	return _commit(next,consumption)

func _research_record(s: Dictionary, id: String, title: String, english: String, memo: String) -> Dictionary:
	var ingredients: Array=[]
	var glass: Dictionary=s.result.contents
	var amounts: Dictionary=glass.contents.duplicate(true)
	amounts.merge(glass.get("solids",{}))
	for garnish in garnishes(glass): amounts[garnish]=float(amounts.get(garnish,0))+1
	for material in amounts:
		var definition: Dictionary=MATERIALS.get(material,SOLIDS.get(material,GARNISHES.get(material,{})))
		var unit: String="ml" if MATERIALS.has(material) else str(definition.get("unit","份"))
		var inventory_unit: String=str(Supplies.get_item(definition.sku_id).get("measurement_unit",unit))
		ingredients.append({"sku_id":definition.sku_id,"name":definition.name,"amount":amounts[material],"unit":unit,"inventory_amount":amounts[material],"inventory_unit":inventory_unit,"required":true,"use":"装饰" if GARNISHES.has(material) else "原料"})
	var instructions: Array=["按成品用量取料；损耗和留在其他容器的材料不写入配方。"]
	var used: Dictionary={}
	for action in s.actions:
		if action.kind in ["shake","stir","muddle"]: used[action.kind]=true
	for kind in used: instructions.append("试调使用过%s；请在复做笔记中记录你的顺序与时长。" % {"shake":"摇和","stir":"搅拌","muddle":"轻压"}[kind])
	instructions.append("出品冰 %s g；以成品预览中的杯型和装饰为参考。" % format_amount(ice_mass(glass)))
	var record: Dictionary={"id":id,"version":1,"name":title,"english_name":english,"notes":memo,"drink_id":s.result.drink_id,"ingredients":ingredients,"instructions":instructions,"result":s.result.duplicate(true),"attributes":s.result.evaluation.attributes.duplicate(true),"model_version":s.result.evaluation.version,"source_kind":"diy","unlocked":true,"type":"DIY","category":"DIY","tags":[],"mouthfeel_tags":[],"flavor_tags":[],"preview_only":true}
	record.merge(record.attributes)
	record.story=memo if not memo.is_empty() else "这页记录了你的实际试调。可在研发室查看原杯和复做参考；不自动加入营业酒单。"
	record.preparation="试调成品用量已记录。请结合右侧参考步骤与笔记再次调制。"
	if s.has("base_recipe"): record.base_recipe_ref={"id":s.base_recipe.id,"version":s.base_recipe.version}
	record.glass={"highball":"高球杯","coupe":"碟形杯","rocks":"古典杯","glass_cocktail_glass":"鸡尾酒杯","glass_balloon_glass":"球形杯"}[s.cup]
	record.display_steps=[]
	for line in instructions: record.display_steps.append({"number":record.display_steps.size()+1,"instruction":line})
	record.ice=[]
	for batch in ice_batches(glass): record.ice.append({"name":"方冰" if batch.kind=="cube" else "碎冰","amount":batch.get("mass_g",batch.volume),"unit":"g"})
	return record

func _error(message: String) -> bool:
	last_error = message
	return false

# Partial pours take upper layers first and move whole ice pieces. Remaining
# fractions stay in the source; no warehouse operations occur during transfer.
func _pour_contents(source: Dictionary, target: Dictionary, free: float, filtered: bool) -> Dictionary:
	var liquid:=amount(source)
	var wanted_ice:=0.0 if filtered else ice_volume(source)
	var ratio:=minf(1,free/maxf(.00001,liquid+wanted_ice))
	var ice_budget:=maxf(0,free-liquid*ratio)
	var moved_ice:=0.0
	var source_batches: Array=[]
	var target_batches:=ice_batches(target)
	if not filtered:
		for batch in ice_batches(source):
			var pieces:=int(batch.get("pieces",4 if batch.kind=="cube" else 10))
			var per_piece:=float(batch.volume)/pieces
			var take:=mini(pieces,int(floor((ice_budget+.00001)/per_piece))) if target_batches.size()<20 else 0
			if take>0:
				var moved: Dictionary=batch.duplicate(true)
				moved.volume=per_piece*take
				moved.mass_g=moved.volume
				moved.pieces=take
				target_batches.append(moved)
				moved_ice+=float(moved.volume)
				ice_budget-=float(moved.volume)
			if take<pieces:
				var left: Dictionary=batch.duplicate(true)
				left.volume=per_piece*(pieces-take)
				left.mass_g=left.volume
				left.pieces=pieces-take
				source_batches.append(left)
		_set_ice(source,source_batches)
		_set_ice(target,target_batches)
	var ml:=minf(liquid,maxf(0,free-moved_ice))
	var fraction:=ml/liquid if liquid>.00001 else ratio
	var stream:=LiquidState.take(source,ml)
	for layer in stream: LiquidState.add(target,layer.contents)
	var solids: Dictionary={}
	var garnish_count:=0
	if not filtered:
		if not target.has("solids"): target.solids={}
		for material in source.get("solids",{}).keys():
			var moved:=float(source.solids[material]) if fraction>=.999999 else floorf(float(source.solids[material])*fraction)
			if moved<=0: continue
			solids[material]=moved
			if material==Muddle.LEAF: Muddle.transfer(source,target,int(moved))
			target.solids[material]=float(target.solids.get(material,0))+moved
			source.solids[material]-=moved
			if source.solids[material]<.000001: source.solids.erase(material)
		var source_garnishes:=garnishes(source)
		var target_garnishes:=garnishes(target)
		garnish_count=mini(int(ceil(source_garnishes.size()*fraction)),MAX_GARNISHES-target_garnishes.size())
		for i in range(garnish_count): target_garnishes.append(source_garnishes.pop_front())
		source.garnishes=source_garnishes
		source.garnish=not source_garnishes.is_empty()
		target.garnishes=target_garnishes
		target.garnish=not target_garnishes.is_empty()
	return {"contents":LiquidState.aggregate(stream),"layers":stream,"fraction":fraction,"ml":ml,"ice_g":moved_ice,"solids":solids,"garnish_count":garnish_count,"source_ice_left":ice_volume(source)>0}

func _set_ice(v: Dictionary, batches: Array) -> void:
	v.ice_batches=batches
	v.ice="none" if batches.is_empty() else batches[0].kind

func _repair_gin_tonic_evaluations(saved: Dictionary) -> bool:
	var definitions:=MATERIALS.duplicate(true)
	definitions.merge(SOLIDS)
	definitions.merge(GARNISHES)
	var version:=str(Evaluation.config().version)
	var sessions: Array=saved.get("history",[]).duplicate()
	sessions.append(saved.get("session",{}))
	var repaired:=false
	for session: Dictionary in sessions:
		if session.get("status")!="finished" or session.get("recipe",{}).get("id")!="gin_and_tonic": continue
		var result: Dictionary=session.get("result",{})
		if result.get("evaluation",{}).get("version")==version: continue
		result.evaluation=Evaluation.evaluate(session,definitions)
		repaired=true
	return repaired
