extends Node
## Startup runs before services: detect legacy files before they create fresh saves.
signal changed
const TUTORIAL_PATH := "res://data/opening/tutorial.json"
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
	return {"version":1,"story_version":2,"node_id":str(story.nodes[0].id),"phase":"new","node":0,"choices":{},"mail_read":{},"tutorial":{},"stock":{},"tutorial_status":"not_started","reward_claimed":false,"legacy":false,"arrival_pending":false}

func node_index(id: String) -> int:
	for i in range(story.nodes.size()):
		if story.nodes[i].id==id: return i
	return -1

func upgrade_story_progress(value: Variant) -> Variant:
	# Old saves used array offsets. Recover their original scene before inserting new dialogue.
	# This only builds an in-memory copy: a damaged save is never rewritten here.
	if not value is Dictionary or value.get("version")!=1: return value
	if value.has("story_version"): return value
	var old_index: Variant=value.get("node")
	var legacy: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/opening/story-v1-index.json"))
	if not (old_index is int or old_index is float) or not is_finite(float(old_index)): return value
	if old_index<0 or old_index!=floor(old_index) or old_index>=legacy.size() or not value.get("choices") is Dictionary: return value
	var next: Dictionary=value.duplicate(true)
	next.node_id=str(legacy[int(old_index)])
	next.node=node_index(next.node_id)
	next.story_version=2
	next.mail_read={}
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
	if value.get("phase") not in ["new","cg","tutorial","ending","ready"]: return false
	if not (value.get("node") is int or value.get("node") is float) or value.node < 0 or value.node != floor(value.node): return false
	var nodes: Array = story.nodes
	if value.node >= nodes.size(): return false
	if value.get("story_version")!=2 or value.get("node_id")!=nodes[int(value.node)].id: return false
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
	next.phase = "cg"
	return _commit(next)

func advance(node: int, choice: String = "") -> bool:
	if node<0 or node>=story.nodes.size(): return false
	var next := state.duplicate(true)
	next.node = node
	next.node_id = str(story.nodes[node].id)
	if not choice.is_empty(): next.choices[str(state.node_id)] = choice
	return _commit(next)

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
	leave_tutorial()
	return true

func finish_opening() -> bool:
	if state.phase != "ending": return false
	if replaying:
		return_to_title()
		return true
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
	if not GameSession.writable or not WorkbenchSession.writable or not SlotWallet.writable or not PlayModes.writable or not Supplies.writable or not MenuCatalog.writable or not StoryDialogue.writable or not CustomerService.writable:
		last_error = "现有存档需要恢复，已保留原文件，暂未进入游戏。"
		return false
	leave_tutorial()
	front_end = false
	Navigation.current_route = &"home"
	SaloonAudio.hall_path = ""
	TimeManager.set_running(true)
	get_tree().change_scene_to_file("res://scenes/home.tscn")
	return true

func arrival_pending() -> bool:
	return not replaying and bool(state.get("arrival_pending",false))

func acknowledge_arrival() -> bool:
	var next := state.duplicate(true)
	next.arrival_pending = false
	return _commit(next)

func return_to_title() -> void:
	leave_tutorial()
	if replaying:
		state = _return_state
		save_path = _return_path
		replaying = false
	front_end = true
	TimeManager.set_running(false)
	GameSession.home = null
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
