extends Node
## A single snapshot keeps the clock, active reception and story progress together.
## The slot wallet retains its own durable spin transaction protocol.
var save_path := "user://game_session.json"
var home: Control
var visit: Dictionary = {}
var last_error := ""
var writable := true
var resetting := false
var dirty := false
var _since_save := 0.0

func _ready() -> void:
	# Older test scenes already isolate the dialogue/wallet; isolate this save too.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dialogue-save="):
			save_path = arg.trim_prefix("--dialogue-save=") + ".session"
		elif arg.begins_with("--slot-wallet=") and save_path == "user://game_session.json":
			save_path = arg.trim_prefix("--slot-wallet=") + ".session"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game-save="):
			save_path = arg.trim_prefix("--game-save=")
	load_game()
	TimeManager.time_changed.connect(func(_day, _minute): dirty = true)
	TimeManager.fast_forward_changed.connect(func(_active): dirty = true)
	StoryDialogue.changed.connect(func():
		if is_instance_valid(home) and not resetting:
			save_game()
	)

func _process(delta: float) -> void:
	_since_save += delta
	if dirty and _since_save >= 0.5 and is_instance_valid(home) and not resetting:
		save_game()

func _exit_tree() -> void:
	if dirty and not resetting:
		save_game()

func bind_home(value: Control) -> void:
	home = value

func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(value) and value >= minimum and value <= maximum

func _valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1:
		return false
	if data.get("reset_pending", false):
		return data.reset_pending is bool
	var clock = data.get("clock")
	if not clock is Dictionary or not _whole(clock.get("day"), 1, 1000000000) or not _whole(clock.get("minutes"), 0, 1439):
		return false
	for key in ["elapsed", "fast_elapsed"]:
		if not (clock.get(key) is float or clock.get(key) is int) or not is_finite(float(clock[key])) or clock[key] < 0:
			return false
	if clock.elapsed >= 1 or clock.fast_elapsed > TimeManager.FAST_FORWARD_SECONDS or not clock.get("fast_forwarding") is bool:
		return false
	if not _whole(clock.get("fast_total"), 0, 1439) or not _whole(clock.get("fast_applied"), 0, int(clock.fast_total)):
		return false
	if not clock.get("closing_pending", false) is bool: return false
	if clock.get("closing_pending", false):
		if int(clock.minutes) != TimeManager.CLOSE_MINUTE or clock.fast_forwarding or not data.get("active") is Dictionary or str(data.active.get("guest_id", "")).is_empty(): return false
	if not StoryDialogue._valid_save(data.get("story")) or not StoryDialogue.valid_session(data.get("active")):
		return false
	var reception = data.get("visit")
	if not reception is Dictionary or not _whole(reception.get("count", 0), 0, 1000000000) or not reception.get("bag", []) is Array:
		return false
	if not reception.get("closing_pending",false) is bool or not _whole(reception.get("closing_day",0),0,1000000000): return false
	if not reception.get("id","") is String: return false
	var seen: Array = []
	for index in reception.get("bag", []):
		if not _whole(index, 0, StoryDialogue.catalog.size() - 1) or seen.has(int(index)):
			return false
		seen.append(int(index))
	return true

func load_game() -> bool:
	writable = true
	last_error = ""
	visit = {}
	if not FileAccess.file_exists(save_path):
		return true # First upgrade retains legacy stories and wallet; old builds stored no clock.
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not _valid(data):
		writable = false
		last_error = "上次的营业记录未能读取，原记录已保留。"
		return false
	if data.get("reset_pending", false):
		return _finish_restart()
	TimeManager.restore(data.clock)
	StoryDialogue.progress = data.story.guests.duplicate(true)
	StoryDialogue.migrate_content_progress()
	StoryDialogue.restore_session(data.active)
	visit = data.visit.duplicate(true)
	dirty = false
	return true

func _capture() -> Dictionary:
	if is_instance_valid(home):
		var guests = home.get_node("%GuestLayer")
		visit = {"count": home.guest_count, "bag": guests._bag.duplicate(), "last_id": guests._last_id, "id":home.reception_id, "closing_pending":home.closing_pending, "closing_day":home.closing_day}
	return {"version": 1, "clock": TimeManager.snapshot(),
		"story": {"version": 1, "guests": StoryDialogue.progress.duplicate(true)},
		"active": StoryDialogue.session_snapshot(), "visit": visit, "reset_pending": false}

func _write(data: Dictionary) -> bool:
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "进度未能保存，请检查存储空间后重试。"
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path + ".tmp"), ProjectSettings.globalize_path(save_path)) != OK:
		last_error = "进度未能保存，请重试。"
		return false
	last_error = ""
	return true

func save_game() -> bool:
	if not writable or resetting:
		return false
	var ok := _write(_capture())
	if ok:
		dirty = false
		_since_save = 0.0
	return ok

func restart_game() -> bool:
	if not SlotWallet.pending.is_empty():
		last_error = "请先等待本轮老虎机结算完成。"
		return false
	# Keep a recoverable copy before a deliberate restart, even if an old save is invalid.
	var directory := ProjectSettings.globalize_path(save_path).get_base_dir().path_join("backups/restart-%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		last_error = "旧进度未能备份，暂未重新开始。"
		return false
	var index := 0
	var restart_paths := [save_path, save_path+".modes", StoryDialogue.save_path, SlotWallet.save_path, MenuCatalog.save_path, CustomerService.save_path]
	var supplies := get_node_or_null("/root/Supplies")
	if supplies != null:
		restart_paths.append(supplies.save_path)
	for path in restart_paths:
		if FileAccess.file_exists(path):
			if DirAccess.copy_absolute(ProjectSettings.globalize_path(path), directory.path_join("%d-%s" % [index, path.get_file()])) != OK:
				last_error = "旧进度未能备份，暂未重新开始。"
				return false
		index += 1
	# Durable intent lets the next launch finish an interrupted multi-file reset.
	if not _write({"version": 1, "reset_pending": true}):
		return false
	return _finish_restart()

func _finish_restart() -> bool:
	resetting = true
	writable = true
	var modes:=get_node_or_null("/root/PlayModes")
	if modes!=null:
		if not modes.reset_game(): return false
	elif FileAccess.file_exists(save_path+".modes"):
		if DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path+".modes"))!=OK: return false
	if not MenuCatalog.reset_game():
		last_error = "酒单尚未重置，请重试。"
		return false
	var supplies := get_node_or_null("/root/Supplies")
	if supplies != null and not supplies.reset_game():
		last_error = "库存尚未重置，请重试。"
		return false
	SlotWallet.balance = 300
	SlotWallet.pending = []
	SlotWallet.hidden_misses = 0
	SlotWallet.spin_count = 0
	SlotWallet.hidden_prizes = []
	SlotWallet.purchase_receipts = {}
	SlotWallet.sale_receipts = {}
	SlotWallet.recovered_payout = -1
	SlotWallet.recovered_hidden = false
	SlotWallet.writable = true
	if not SlotWallet.persist():
		last_error = "重新开始尚未完成，请重试。"
		return false
	if not CustomerService.reset_game():
		last_error = "客人记录尚未重置，请重试。"
		return false
	StoryDialogue.progress = {}
	StoryDialogue.end_guest()
	StoryDialogue.writable = true
	StoryDialogue._save()
	if not StoryDialogue.last_error.is_empty():
		last_error = "重新开始尚未完成，请重试。"
		return false
	TimeManager.restore({})
	visit = {}
	# Do not capture the old home while replacing its state.
	var old_home := home
	home = null
	var saved := _write(_capture())
	home = old_home
	if not saved:
		return false
	resetting = false
	dirty = false
	return true
