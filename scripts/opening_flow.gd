extends Node
## Startup runs before services: detect legacy files before they create fresh saves.
signal changed
const TUTORIAL_PATH := "res://data/opening/tutorial.json"
const PLAYER_NAME_LIMIT := 16
var story: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/opening/story.json"))
var save_path := "user://game_session.json.opening"
var state: Dictionary = {}
var front_end := true
var replaying := false
var writable := true
var last_error := ""
var _return_state: Dictionary = {}
var _return_path := ""
var reduced_motion := false

func _ready() -> void:
	for arg in OS.get_cmdline_args():
		if arg.ends_with(".tscn") and not arg.ends_with("title_screen.tscn"):
			front_end = false
	var game := "user://game_session.json"
	var legacy_paths: Array[String] = [game,"user://story_progress.json","user://wallet.json","user://supplies_state.json","user://menu_state.json","user://workbench_practice.json"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dialogue-save="):
			game = arg.trim_prefix("--dialogue-save=") + ".session"
		elif arg.begins_with("--slot-wallet=") and game == "user://game_session.json":
			game = arg.trim_prefix("--slot-wallet=") + ".session"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game-save="): game = arg.trim_prefix("--game-save=")
	if game != "user://game_session.json":
		legacy_paths = [game,game+".modes",game+".supplies",game+".menu"]
		for arg in OS.get_cmdline_user_args():
			for prefix in ["--dialogue-save=","--slot-wallet=","--supplies-save=","--menu-save=","--workbench-save="]:
				if arg.begins_with(prefix): legacy_paths.append(arg.trim_prefix(prefix))
	save_path = game + ".opening"
	state = fresh()
	if FileAccess.file_exists(save_path):
		var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		loaded = upgrade_story_progress(loaded)
		if not valid(loaded):
			writable = false
			last_error = "序章进度无法读取，原记录已保留。请恢复备份后继续。"
		else: state = loaded
	else:
		for path in legacy_paths:
			if FileAccess.file_exists(path):
				state.phase = "ready"
				state.legacy = true
				break
		if front_end: _commit(state) # A fresh marker survives quitting on the title screen.
	var config := ConfigFile.new()
	if config.load(save_path+".settings") == OK:
		reduced_motion = bool(config.get_value("display","reduced_motion",false))

func fresh() -> Dictionary:
	return {"version":1,"story_version":4,"node_id":str(story.nodes[0].id),"phase":"new","node":0,"choices":{},"mail_read":{},"history":[],"tutorial":{},"stock":{},"tutorial_status":"not_started","reward_claimed":false,"legacy":false,"arrival_pending":false}

func node_index(id: String) -> int:
	for i in range(story.nodes.size()):
		if story.nodes[i].id==id: return i
	return -1

func upgrade_story_progress(value: Variant) -> Variant:
	if not value is Dictionary or value.get("version")!=1: return value
	if value.get("story_version")==4: return value
	if value.has("story_version") and value.story_version not in [2,3]: return value
	if not value.get("mail_read",{}) is Dictionary: return value
	var generation:=int(value.get("story_version",1))
	var legacy: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/opening/story-v%d-index.json" % generation))
	var old_index: Variant=value.get("node")
	if not (old_index is int or old_index is float) or not is_finite(float(old_index)): return value
	if old_index<0 or old_index!=floor(old_index) or old_index>=legacy.size() or not value.get("choices") is Dictionary: return value
	if value.has("story_version") and value.get("node_id")!=legacy[int(old_index)]: return value
	var next: Dictionary=value.duplicate(true)
	var resume:=int(old_index)
	while resume<legacy.size() and node_index(str(legacy[resume]))<0: resume+=1
	if resume>=legacy.size(): return value
	next.node_id=str(legacy[resume])
	next.node=node_index(next.node_id)
	next.story_version=4
	next.mail_read=value.get("mail_read",{}).duplicate(true)
	next.history=[]
	if generation==3:
		if not value.get("history") is Array: return value
		var seen: Dictionary={}
		for id in value.history:
			if not id is String or not legacy.has(id) or seen.has(id): return value
			seen[id]=true
			if node_index(id)>=0: next.history.append(id)
	elif value.get("phase","new")!="new" and not value.get("legacy",false):
		for i in range(int(old_index)+1):
			if node_index(str(legacy[i]))>=0: next.history.append(str(legacy[i]))
	next.choices={}
	for key in value.choices:
		var id:=str(key)
		if id.is_valid_int():
			var old_choice:=int(id)
			if old_choice<0 or old_choice>=legacy.size(): return value
			id=str(legacy[old_choice])
		next.choices[id]=value.choices[key]
	return next

func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1: return false
	var saved_name: Variant=value.get("player_name","")
	if not saved_name is String: return false
	if not saved_name.is_empty() and (not player_name_error(saved_name).is_empty() or saved_name!=saved_name.strip_edges()): return false
	if value.get("phase") not in ["new","cg","tutorial","ending","ready"]: return false
	if value.has("departure") and not valid_departure(value.departure): return false
	if not (value.get("node") is int or value.get("node") is float) or value.node < 0 or value.node != floor(value.node): return false
	var nodes: Array = story.nodes
	if value.node >= nodes.size(): return false
	if value.get("story_version")!=4 or value.get("node_id")!=nodes[int(value.node)].id: return false
	if not value.get("history") is Array or value.history.size()>nodes.size(): return false
	var seen: Dictionary={}
	for id in value.history:
		if not id is String or node_index(id)<0 or seen.has(id): return false
		seen[id]=true
	if not value.get("mail_read") is Dictionary: return false
	for id in value.mail_read:
		if not story.mail.has(id) or not value.mail_read[id] is bool: return false
	for field in ["choices","tutorial","stock"]:
		if not value.get(field) is Dictionary: return false
	for amount in value.stock.values():
		if not (amount is float or amount is int) or not is_finite(amount) or amount < 0 or amount > 100000: return false
	return value.get("tutorial_status") in ["not_started","active","completed","skipped"] and value.get("reward_claimed") is bool and value.get("legacy") is bool

func _commit(next: Dictionary) -> bool:
	if not writable or not valid(next):
		last_error = "序章状态无法保存，请保留当前进度。"
		return false
	var f := FileAccess.open(save_path+".tmp",FileAccess.WRITE)
	if f == null:
		last_error = "序章保存失败，请检查存储空间后重试。"
		return false
	f.store_string(JSON.stringify(next))
	f.flush()
	var ok := f.get_error() == OK
	f.close()
	if not ok or DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path+".tmp"),ProjectSettings.globalize_path(save_path)) != OK:
		last_error = "序章保存失败，尚未离开当前节点。"
		return false
	state = next.duplicate(true)
	last_error = ""
	changed.emit()
	return true

func set_reduced_motion(value: bool) -> void:
	reduced_motion = value
	var config := ConfigFile.new()
	config.set_value("display","reduced_motion",value)
	config.save(save_path+".settings")

func begin_story() -> bool:
	var next := fresh()
	if replaying: next.player_name=_return_state.get("player_name","")
	next.phase = "cg"
	next.history.append(str(next.node_id))
	return _commit(next)

func advance(node: int, choice: String = "") -> bool:
	if node<0 or node>=story.nodes.size(): return false
	var next := state.duplicate(true)
	next.node = node
	next.node_id = str(story.nodes[node].id)
	if not next.history.has(next.node_id): next.history.append(str(next.node_id))
	if not choice.is_empty(): next.choices[str(state.node_id)] = choice
	return _commit(next)

func history_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary]=[]
	for id: String in state.history:
		var node: Dictionary=story.nodes[node_index(id)]
		entries.append({"chapter":node.chapter+" · "+node.title,"speaker":node.speaker,"text":node.text})
		var selected:=str(state.choices.get(id,""))
		for choice: Dictionary in node.get("choices",[]):
			if selected==choice.text:
				entries.append({"chapter":"","speaker":"我 · 当时的选择","text":selected+"\n"+str(choice.reply)})
		var mail_id:=str(node.get("mail_id",""))
		if not mail_id.is_empty() and state.mail_read.get(mail_id,false):
			var mail: Dictionary=story.mail[mail_id]
			entries.append({"chapter":"","speaker":"邮件 · "+str(mail.subject),"text":str(mail.sender)+"\n\n"+str(mail.body)})
	return entries

func mark_mail_read(id: String) -> bool:
	if not story.mail.has(id) or story.nodes[int(state.node)].get("mail_id","")!=id: return false
	if bool(state.mail_read.get(id,false)): return true
	var next:=state.duplicate(true)
	next.mail_read[id]=true
	return _commit(next)

func begin_replay() -> bool:
	if replaying: return false
	_return_state = state.duplicate(true)
	_return_path = save_path
	save_path += ".replay"
	replaying = true
	if begin_story(): return true
	save_path = _return_path
	state = _return_state
	replaying = false
	return false

func tutorial_config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(TUTORIAL_PATH))

func begin_tutorial(reset := false) -> bool:
	if not WorkbenchSession.writable: return false
	var next := state.duplicate(true)
	if reset or next.tutorial.is_empty():
		var bench := WorkbenchSession.snapshot()
		# Shared achievements and research remain visible but only this isolated copy changes.
		bench.serial += 1
		bench.session = WorkbenchSession._session(int(bench.serial))
		bench.session.id = "opening-%d-%d" % [int(Time.get_unix_time_from_system()),Time.get_ticks_usec()]
		bench.session.tutorial = true
		bench.session.recipe = WorkbenchSession.recipe_snapshot(MenuCatalog.get_recipe("echo_world"))
		WorkbenchSession.set_cup(bench.session,"highball")
		bench.table_materials = []
		bench.receipts = {}
		bench.history = []
		next.tutorial = bench
		next.stock = tutorial_config().stock.duplicate(true)
	if not WorkbenchSession._valid(next.tutorial):
		last_error = "教学杯记录不完整，原记录已保留。"
		return false
	next.phase = "tutorial"
	next.tutorial_status = "active"
	if not _commit(next): return false
	WorkbenchSession.tutorial_active = true
	WorkbenchSession.state = next.tutorial.duplicate(true)
	WorkbenchSession._refresh_stock_view()
	WorkbenchSession.changed.emit()
	return true

func commit_tutorial(bench: Dictionary, consumption: Dictionary) -> bool:
	if state.phase != "tutorial" or not WorkbenchSession._valid(bench):
		last_error = "教学记录校验失败，未扣除材料。"
		return false
	var next := state.duplicate(true)
	for id in consumption:
		var amount := float(consumption[id])
		if not is_finite(amount) or amount <= 0 or float(next.stock.get(id,0)) < amount:
			last_error = "教学材料不足。按 N 重新准备教学包，不消耗仓库原料。"
			return false
		next.stock[id] = float(next.stock[id]) - amount
	next.tutorial = bench.duplicate(true)
	next.tutorial.erase("stock")
	next.tutorial.erase("garnish_stock")
	return _commit(next)

func leave_tutorial() -> void:
	if not WorkbenchSession.tutorial_active: return
	WorkbenchSession.tutorial_active = false
	WorkbenchSession._warehouse_changed()

func finish_tutorial(skipped := false) -> bool:
	if not skipped and state.tutorial.get("session",{}).get("status") != "finished":
		last_error = "先把杯中作品完成，或选择跳过教学。"
		return false
	var next := state.duplicate(true)
	next.phase = "ending"
	next.tutorial_status = "skipped" if skipped else "completed"
	if not _commit(next): return false
	# The durable tutorial milestone is written first. A failed catalogue write
	# can be retried, or reconciled on the next startup, without replaying practice.
	if not replaying and not MenuCatalog.unlock_recipe("echo_world"):
		last_error = MenuCatalog.last_error
		return false
	leave_tutorial()
	return true

func departure_nodes() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/opening/departure.json")).nodes

func valid_departure(value: Variant) -> bool:
	if not value is Dictionary or not value.get("node") is String or not value.get("seen") is Array or not value.get("recipe") is String: return false
	var ids: Array=[]
	for row: Dictionary in departure_nodes(): ids.append(row.id)
	if not ids.has(value.node) or value.seen.size()>ids.size(): return false
	var seen: Array=[]
	for row in value.seen:
		if not row is Dictionary or not ids.has(row.get("id")) or seen.has(row.id): return false
		if not row.get("text") is String or not row.get("speaker") is String or not row.get("chapter") is String: return false
		seen.append(row.id)
	for flag in ["signed","water","opened","merchant_met","seed_heard"]:
		if not value.get(flag) is bool: return false
	if value.has("lesson"):
		var lesson: Variant=value.lesson
		if not lesson is Dictionary or lesson.get("phase") not in ["shop","mixing","complete"]: return false
		if not lesson.get("accepted_drink","") is String: return false
	return true

func begin_departure() -> bool:
	if state.phase!="ending": return false
	if not replaying and not MenuCatalog.unlock_recipe("echo_world"):
		last_error=MenuCatalog.last_error
		return false
	if state.has("departure"): return true
	var next:=state.duplicate(true)
	next.departure={"node":"cup_today","seen":[],"recipe":"echo_world","signed":false,"water":false,"opened":false,"merchant_met":false,"seed_heard":false}
	return _commit(next)

func update_departure(patch: Dictionary) -> bool:
	if state.phase!="ending" or not state.has("departure"): return false
	var next:=state.duplicate(true)
	for key in patch:
		if not next.departure.has(key) and key!="lesson": return false
		next.departure[key]=patch[key]
	return _commit(next)

func player_name_error(value: String) -> String:
	var clean:=value.strip_edges()
	if clean.is_empty(): return "请先写下你的名字。"
	if clean.length()>PLAYER_NAME_LIMIT: return "名字最多 16 个字。"
	for i in range(clean.length()):
		var code:=clean.unicode_at(i)
		if code<32 or (code>=127 and code<=159) or code in [0x200B,0x200C,0x200D,0x2028,0x2029,0xFEFF] or (code>=0x202A and code<=0x202E) or (code>=0x2060 and code<=0x206F):
			return "名字请使用可见文字，不要包含换行或隐藏字符。"
	return ""

func protagonist_name() -> String:
	var value:=str(state.get("player_name",""))
	return "我" if value.is_empty() else value

func protagonist_speaker(value: String) -> String:
	if value=="我": return protagonist_name()
	if value.begins_with("我 · "): return protagonist_name()+value.trim_prefix("我")
	return value

func sign_receipt(value: String) -> bool:
	last_error=player_name_error(value)
	if not last_error.is_empty(): return false
	if state.phase!="ending" or not state.has("departure"):
		last_error="请在收货签认时填写名字。"
		return false
	var clean:=value.strip_edges()
	if state.departure.signed:
		return state.get("player_name","")==clean
	if state.departure.node!="sign_receipt":
		last_error="请在收货签认时填写名字。"
		return false
	var next:=state.duplicate(true)
	next.player_name=clean
	next.departure.signed=true
	var rows:=departure_nodes()
	for i in range(rows.size()-1):
		if rows[i].id=="sign_receipt":
			next.departure.node=rows[i+1].id
			return _commit(next) # Name, signature and cursor succeed or fail together.
	return false

func observe_departure(row: Dictionary) -> bool:
	for seen: Dictionary in state.departure.seen:
		if seen.id==row.id: return true
	var seen: Array=state.departure.seen.duplicate(true)
	seen.append({"id":row.id,"chapter":row.chapter,"speaker":row.speaker,"text":row.text})
	return update_departure({"seen":seen})

func finish_opening() -> bool:
	if OpeningTransition.busy: return false
	if state.phase != "ending": return false
	if replaying:
		return_to_title()
		return true
	if not state.get("departure",{}).get("opened",false) or not preload("res://scripts/opening_preparation.gd").ready_menu():
		last_error="先备齐一款酒、确认上架，再翻转营业牌。"
		return false
	# Unlocking an official ID is idempotent; no menu insertion, sales or guest progress.
	if not MenuCatalog.unlock_recipe("echo_world"):
		last_error = MenuCatalog.last_error
		return false
	var next := state.duplicate(true)
	next.phase = "ready"
	next.reward_claimed = true
	next.arrival_pending = true
	if not _commit(next): return false
	return enter_game()

func enter_game() -> bool:
	if OpeningTransition.busy: return false
	if not GameSession.writable or not WorkbenchSession.writable or not SlotWallet.writable or not PlayModes.writable or not Supplies.writable or not MenuCatalog.writable or not StoryDialogue.writable or not CustomerService.writable:
		last_error = "现有存档需要恢复，已保留原文件，暂未进入游戏。"
		return false
	leave_tutorial()
	front_end = false
	Navigation.current_route = &"home"
	SaloonAudio.hall_path = ""
	TimeManager.set_running(not arrival_pending())
	return OpeningTransition.go("res://scenes/home.tscn")

func arrival_pending() -> bool:
	return not replaying and bool(state.get("arrival_pending",false))

func acknowledge_arrival() -> bool:
	var next := state.duplicate(true)
	next.arrival_pending = false
	return _commit(next)

func return_to_title() -> void:
	if OpeningTransition.busy: return
	leave_tutorial()
	if replaying:
		state = _return_state
		save_path = _return_path
		replaying = false
	front_end = true
	TimeManager.set_running(false)
	GameSession.home = null
	OpeningTransition.go("res://scenes/title_screen.tscn","title")
