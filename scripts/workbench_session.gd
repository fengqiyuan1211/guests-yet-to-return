extends Node
const LiquidState=preload("res://scripts/workbench_liquid_state.gd")
const LiquidAppearance=preload("res://scripts/workbench_liquid_appearance.gd")
## Production actions and warehouse stock commit together through Supplies.
## No sale or guest settlement is performed here.
signal changed
const Evaluation=preload("res://scripts/workbench_evaluation.gd")
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
	return {"schema":2,"table_materials":[],"serial":0,"session":{},"receipts":{},"history":[]}

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
	return {"liquid_profiles":LiquidAppearance.profiles(),"liquid_model":LiquidState.config(),"id": "practice-%d" % serial, "mode": "workbench", "status": "mixing", "recipe": RECIPE.duplicate(true), "vessels": vessels, "lid": false, "cup": "coupe", "vessel_capacities":capacities, "spoon_vessel":"", "actions": [], "withdrawn": {}, "consumed": {}, "result": {}}

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
	if not s.get("id") is String or s.get("mode") not in ["practice","workbench"] or s.get("status") not in ["mixing", "finished", "discarded"]:
		return false
	if not s.get("recipe") is Dictionary or not s.get("actions") is Array or not s.get("result") is Dictionary or not s.get("withdrawn") is Dictionary or not s.get("lid") is bool or s.get("cup") not in CUPS:
		return false
	if s.has("liquid_profiles") and not LiquidAppearance.valid_snapshot(s.liquid_profiles): return false
	if s.has("liquid_model") and not LiquidState.valid_model(s.liquid_model): return false
	if s.result.has("liquid_profiles") and not LiquidAppearance.valid_snapshot(s.result.liquid_profiles): return false
	if s.result.has("liquid_model") and not LiquidState.valid_model(s.result.liquid_model): return false
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
	if not s.get("guest",{}) is Dictionary: return false
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
	# Content hash is a revision identifier when the catalog has no numbered version.
	result.version = reference.get("version", JSON.stringify(reference).sha256_text())
	# Normalize numeric types to the same JSON representation used by saved cups.
	return JSON.parse_string(JSON.stringify(result))

func _valid_recipe_snapshot(recipe: Dictionary) -> bool:
	if recipe.get("practice_only")==true: return true
	if recipe.get("source_kind")!="menu_catalog" or not recipe.get("id") is String or not recipe.get("ingredient_rows") is Array: return false
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

func dose_target(material: String, session: Dictionary) -> float:
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
	if not LiquidState.valid(v): return false
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
	var consumption := {}
	var outcome: Dictionary={}
	var s: Dictionary = next.session
	if kind == "select_recipe":
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
				consumption[SOLIDS[material].sku_id]=1
			"transfer", "filter":
				var source_id := str(payload.get("source", "jigger"))
				if not s.vessels.has(source_id) or source_id == vessel_id:
					return _error("请选择另一个接酒容器。")
				var source: Dictionary = s.vessels[source_id]
				if amount(source) <= 0 and (kind=="filter" or (source.get("solids",{}).is_empty() and ice_batches(source).is_empty() and garnishes(source).is_empty())):
					return _error("源容器中还没有液体。")
				var built_in_filter: bool=kind=="filter" and source_id=="shaker" and vessel_id=="glass" and payload.get("integrated_strainer")==true
				if (vessel_id == "shaker" or source_id == "shaker") and s.lid and not built_in_filter:
					return _error("先打开摇壶盖，再倒入或过滤。")
				if kind == "filter" and (vessel_id != "glass" or source_id not in ["shaker", "mixing"]):
					return _error("使用滤冰器将摇壶或搅拌杯倒入成品杯。")
				var incoming_ice:=ice_volume(source) if kind=="transfer" else 0.0
				if kind=="transfer" and vessel_id=="jigger" and (incoming_ice>0 or not source.get("solids",{}).is_empty() or not garnishes(source).is_empty()): return _error("量酒器仅接收酒液，请使用制作容器或成品杯。")
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
				if payload.has("control") and not _number(payload.control,1): return _error("动作节奏数据无效。")
				if not _number(payload.get("seconds"), 0.5) or payload.seconds <= 0:
					return _error("没有检测到有效动作。")
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
			"discard":
				s.status = "discarded"
				s.spoon_vessel=""
				s.result = {"withdrawn": s.withdrawn.duplicate(true), "waste": s.withdrawn.duplicate(true), "consumed":s.get("consumed",{}).duplicate(true), "sales": false}
			_:
				return _error("未知操作。")
		if not s.has("consumed"): s.consumed={}
		for sku in consumption: s.consumed[sku]=float(s.consumed.get(sku,0))+float(consumption[sku])
		var action:={"command_id": id, "kind": kind, "payload": payload.duplicate(true)}
		action.merge(outcome)
		if kind=="ice": action.mass_g=ICE_PORTION_G
		if kind=="transfer": action.transfers_ice=true
		s.actions.append(action)
	next.receipts[id] = signature
	return _commit(next,consumption)

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
