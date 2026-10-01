extends Node
## Isolated practice adapter. Never writes real inventory, menu, wallet or guest state.
## One atomic snapshot owns stock, vessels, actions and idempotency receipts.
signal changed
const RECIPE := {"id": "workbench_practice", "version": 1, "name": "码头试作", "english_name": "Dockside Practice", "practice_only": true, "ingredients": {"gin": 30, "lime": 20, "syrup": 10}}
const MATERIALS := {
	"gin": {"name": "金酒", "en": "GIN", "sku_id": "sku_gin_london_dry", "color": "d7cba8"},
	"rum": {"name":"朗姆酒","en":"RUM","sku_id":null,"color":"ba863e"},
	"vodka": {"name":"伏特加","en":"VODKA","sku_id":null,"color":"ded4ba"},
	"lime": {"name": "青柠汁", "en": "LIME", "sku_id": null, "color": "b0bd66"},
	"syrup": {"name": "糖浆", "en": "SYRUP", "sku_id": null, "color": "cd9950"},
	"soda": {"name": "苏打水", "en": "SODA", "sku_id": null, "color": "a0c6c6"}
}
const CAPACITIES := {"jigger": 90, "shaker": 500, "mixing": 500, "glass": 300}
var save_path := "user://workbench_practice.json"
var state: Dictionary = {}
var last_error := ""
var writable := true

func _ready() -> void:
	for prefix in ["--slot-wallet=", "--dialogue-save=", "--game-save=", "--workbench-save="]:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with(prefix):
				save_path = arg.trim_prefix(prefix) + ("" if prefix == "--workbench-save=" else ".workbench")
	load_state()

func _fresh() -> Dictionary:
	return {"schema": 1, "table_materials": [], "serial": 0, "stock": {"gin": 600, "lime": 600, "syrup": 600, "soda": 600, "rum": 600, "vodka": 600}, "garnish_stock": 20, "session": {}, "receipts": {}, "history": []}

func _session(serial: int) -> Dictionary:
	var vessels := {}
	for id in CAPACITIES:
		vessels[id] = {"contents": {}, "ice": "none", "garnish": false}
	return {"id": "practice-%d" % serial, "mode": "practice", "status": "mixing", "recipe": RECIPE.duplicate(true), "vessels": vessels, "lid": false, "cup": "coupe", "actions": [], "withdrawn": {}, "result": {}}

func snapshot() -> Dictionary:
	return state.duplicate(true)

func amount(vessel: Dictionary) -> int:
	var total := 0
	for value in vessel.contents.values():
		total += int(value)
	return total

func _number(value: Variant, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= maximum

func _valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("schema") != 1:
		return false
	if not _valid_table_materials(data.get("table_materials", [])):
		return false
	for key in ["stock", "receipts", "session"]:
		if not data.get(key) is Dictionary:
			return false
	if not data.get("history") is Array or not _number(data.get("serial"), 1000000000):
		return false
	if not _number(data.get("garnish_stock"), 20):
		return false
	for id in MATERIALS:
		if not _number(data.stock.get(id), 600):
			return false
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
	if not s.get("id") is String or s.get("mode") != "practice" or s.get("status") not in ["mixing", "finished", "discarded"]:
		return false
	if not s.get("recipe") is Dictionary or not s.get("actions") is Array or not s.get("result") is Dictionary or not s.get("withdrawn") is Dictionary or not s.get("lid") is bool or s.get("cup") not in ["rocks", "highball", "coupe"]:
		return false
	if not s.recipe.get("name") is String or not s.recipe.get("english_name") is String or not s.recipe.get("ingredients") is Dictionary or s.recipe.get("practice_only") != true:
		return false
	for material in s.recipe.ingredients:
		if not MATERIALS.has(material) or not _number(s.recipe.ingredients[material],90):
			return false
	for action in s.actions:
		if not action is Dictionary or not action.get("command_id") is String or not action.get("kind") is String or not action.get("payload") is Dictionary:
			return false
		if action.kind not in ["withdraw","transfer","filter","ice","lid","cup","shake","stir","muddle","garnish","finish","discard"]:
			return false
		if action.kind == "withdraw" and (not MATERIALS.has(action.payload.get("material")) or not _number(action.payload.get("ml"),90) or not CAPACITIES.has(action.payload.get("vessel","jigger"))):
			return false
		if action.kind in ["transfer","filter"] and (not CAPACITIES.has(action.payload.get("source")) or not CAPACITIES.has(action.payload.get("vessel"))):
			return false
		if action.kind in ["shake","stir","muddle"] and not _number(action.payload.get("seconds"),.5):
			return false
	if not s.get("vessels") is Dictionary:
		return false
	var retained := {}
	for id in CAPACITIES:
		var v: Variant = s.vessels.get(id)
		if not _valid_vessel(v,CAPACITIES[id]):
			return false
		for material in v.contents:
			retained[material] = int(retained.get(material,0))+int(v.contents[material])
	for material in s.withdrawn:
		if not MATERIALS.has(material) or not _number(s.withdrawn[material],600) or int(s.withdrawn[material]) != int(retained.get(material,0)):
			return false
	for material in retained:
		if not s.withdrawn.has(material):
			return false
	if s.status == "finished":
		if not _valid_vessel(s.result.get("contents"),300) or not s.result.get("waste") is Dictionary or not s.result.get("drink_id") is String:
			return false
		for material in s.result.waste:
			if not MATERIALS.has(material) or not _number(s.result.waste[material],600):
				return false
	return true

func _valid_vessel(v: Variant, capacity: int) -> bool:
	if not v is Dictionary or not v.get("contents") is Dictionary or v.get("ice") not in ["none", "cube", "crushed"] or not v.get("garnish") is bool:
		return false
	for material in v.contents:
		if not MATERIALS.has(material) or not _number(v.contents[material],capacity) or v.contents[material] != floor(float(v.contents[material])):
			return false
	return amount(v) + (40 if v.ice != "none" else 0) <= capacity

func load_state() -> bool:
	writable = true
	last_error = ""
	if not FileAccess.file_exists(save_path):
		state = _fresh()
		return true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if data is Dictionary and data.get("schema") == 1 and data.get("stock") is Dictionary:
		for id in ["rum", "vodka"]:
			if not data.stock.has(id): data.stock[id] = 600
	if not _valid(data):
		state = _fresh()
		writable = false
		last_error = "试作记录未能读取，原文件已保留。"
		return false
	if not data.has("table_materials"): data.table_materials = []
	state = data
	return true

func _commit(next: Dictionary) -> bool:
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "试作进度未能保存，本次操作未生效。"
		return false
	file.store_string(JSON.stringify(next))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path + ".tmp"), ProjectSettings.globalize_path(save_path)) != OK:
		last_error = "试作进度未能保存，本次操作未生效。"
		return false
	state = next
	last_error = ""
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
	var s: Dictionary = next.session
	if kind == "start":
		if not s.is_empty() and s.status == "mixing":
			return _error("桌上还有半成品，请先继续或丢弃。")
		if not s.is_empty():
			next.history.append(s.duplicate(true))
		next.serial += 1
		next.session = _session(int(next.serial))
	else:
		if s.is_empty() or s.id != session_id or s.status != "mixing":
			return _error("这一杯已经结束或已被替换。")
		var vessel_id := str(payload.get("vessel", "jigger" if kind=="withdraw" else "glass"))
		if not s.vessels.has(vessel_id):
			return _error("请先选择桌上的容器。")
		var v: Dictionary = s.vessels[vessel_id]
		match kind:
			"withdraw":
				var material := str(payload.get("material", ""))
				var quantity: Variant = payload.get("ml")
				if not MATERIALS.has(material) or not _number(quantity, 90) or quantity != floor(float(quantity)) or quantity <= 0:
					return _error("量取范围为 1–90 ml。")
				if vessel_id=="shaker" and s.lid:
					return _error("先打开摇壶盖，再加入材料。")
				if amount(v) + int(quantity) + (40 if v.ice!="none" else 0) > CAPACITIES[vessel_id]:
					return _error("接酒容器装不下了，本次未取料。")
				if next.stock[material] < quantity:
					return _error("这份试作材料不足。")
				next.stock[material] -= int(quantity)
				v.contents[material] = int(v.contents.get(material, 0)) + int(quantity)
				s.withdrawn[material] = int(s.withdrawn.get(material, 0)) + int(quantity)
			"transfer", "filter":
				var source_id := str(payload.get("source", "jigger"))
				if not s.vessels.has(source_id) or source_id == vessel_id:
					return _error("请选择另一个接酒容器。")
				var source: Dictionary = s.vessels[source_id]
				if amount(source) <= 0:
					return _error("源容器中还没有液体。")
				if (vessel_id == "shaker" or source_id == "shaker") and s.lid:
					return _error("先打开摇壶盖，再倒入或过滤。")
				if kind == "filter" and (vessel_id != "glass" or source_id not in ["shaker", "mixing"]):
					return _error("使用滤冰器将摇壶或搅拌杯倒入成品杯。")
				if amount(v) + amount(source) + (40 if v.ice != "none" else 0) > CAPACITIES[vessel_id]:
					return _error("接酒容器容量不足，本次没有倒入。")
				for material in source.contents:
					v.contents[material] = int(v.contents.get(material, 0)) + int(source.contents[material])
				source.contents = {}
			"ice":
				if vessel_id == "jigger" or v.ice != "none" or (vessel_id == "shaker" and s.lid):
					return _error("请选一个未加冰、已打开的制作容器。")
				if payload.get("ice") not in ["cube", "crushed"] or amount(v) + 40 > CAPACITIES[vessel_id]:
					return _error("请选择冰型，并确认容器有空间。")
				v.ice = payload.ice
			"lid":
				s.lid = not s.lid
			"cup":
				if payload.get("cup") not in ["rocks", "highball", "coupe"]:
					return _error("未知杯型。")
				s.cup = payload.cup
			"shake", "stir", "muddle":
				if amount(v) == 0:
					return _error("先加入材料再操作。")
				if kind == "shake" and (vessel_id != "shaker" or not s.lid):
					return _error("请选摇壶并盖好盖子。")
				if kind != "shake" and (vessel_id not in ["glass", "mixing", "shaker"] or (vessel_id == "shaker" and s.lid)):
					return _error("请选打开的容器。")
				if not _number(payload.get("seconds"), 0.5) or payload.seconds <= 0:
					return _error("没有检测到有效动作。")
			"garnish":
				if amount(s.vessels.glass) == 0 or s.vessels.glass.garnish or next.garnish_stock < 1:
					return _error("先往成品杯倒入酒液；每杯只放一份装饰。")
				s.vessels.glass.garnish = true
				next.garnish_stock -= 1
			"finish":
				if amount(s.vessels.glass) == 0:
					return _error("请先将酒液倒入成品杯。")
				s.status = "finished"
				var waste := {}
				for source_id in s.vessels:
					if source_id != "glass":
						for material in s.vessels[source_id].contents:
							waste[material] = int(waste.get(material, 0)) + int(s.vessels[source_id].contents[material])
				s.result = {"drink_id": s.id + "-drink", "recipe": s.recipe.duplicate(true), "contents": s.vessels.glass.duplicate(true), "withdrawn": s.withdrawn.duplicate(true), "waste": waste, "actions": s.actions.duplicate(true), "sales": false}
			"discard":
				s.status = "discarded"
				s.result = {"withdrawn": s.withdrawn.duplicate(true), "waste": s.withdrawn.duplicate(true), "sales": false}
			_:
				return _error("未知操作。")
		s.actions.append({"command_id": id, "kind": kind, "payload": payload.duplicate(true)})
	next.receipts[id] = signature
	return _commit(next)

func _error(message: String) -> bool:
	last_error = message
	return false
