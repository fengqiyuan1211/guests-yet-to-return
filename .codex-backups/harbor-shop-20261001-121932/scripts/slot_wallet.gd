extends Node
## Shared home/slot balance. Persist a paid spin and its result before animation.
## On interruption, finish that same saved result once on next load.
signal balance_changed(balance: int)
## Emitted only after a durable settlement; reward delivery is not connected yet.
signal hidden_prize_reserved(record: Dictionary)
const Rules := preload("res://scripts/slot_rules.gd")
var balance := 300
var pending: Array = []
var last_error := ""
var recovered_payout := -1
var recovered_hidden := false
var hidden_misses := 0
var spin_count := 0
var hidden_prizes: Array = []
var save_path := "user://wallet.json"
var rng := RandomNumberGenerator.new()
var writable := true

func _ready() -> void:
	rng.randomize()
	# Isolated wallet path for verification; never touch the player's real save.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slot-wallet="):
			save_path = arg.trim_prefix("--slot-wallet=")
	load_wallet()

func load_wallet() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary or not data.get("balance") is float or not data.get("pending") is Array:
		writable = false
		last_error = "金币记录无法读取，请保留存档后重试。"
		return
	if data.balance < 0 or data.balance != floor(data.balance) or (not data.pending.is_empty() and not Rules.valid_result(data.pending)):
		writable = false
		last_error = "金币记录不完整，暂时无法开始。"
		return
	var version = data.get("version", 1)
	if version != 1 and version != 2:
		writable = false
		last_error = "存档版本不兼容，请保留存档。"
		return
	if version == 2 and not _valid_hidden_data(data):
		writable = false
		last_error = "大奖记录不完整，请保留存档后重试。"
		return
	if version == 1 and Rules.is_hidden(data.pending):
		writable = false
		last_error = "旧存档结果不完整，请保留存档。"
		return
	balance = int(data.balance)
	pending = data.pending
	hidden_misses = int(data.get("hidden_misses", 0))
	spin_count = int(data.get("spin_count", 0))
	hidden_prizes = data.get("hidden_prizes", []).duplicate(true)
	recovered_payout = -1
	recovered_hidden = false
	if not pending.is_empty():
		var was_hidden := Rules.is_hidden(pending)
		recovered_payout = settle_spin()
		recovered_hidden = was_hidden and recovered_payout >= 0

func persist() -> bool:
	if not writable:
		return false
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "金币未能保存，请检查存储空间后重试。"
		return false
	file.store_string(JSON.stringify({"version": 2, "balance": balance, "pending": pending,
		"hidden_misses": hidden_misses, "spin_count": spin_count, "hidden_prizes": hidden_prizes}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(temporary, save_path) != OK:
		last_error = "金币未能保存，请重试。"
		return false
	last_error = ""
	return true

func begin_spin() -> Array:
	if not writable:
		return []
	if not pending.is_empty():
		last_error = "本轮尚未结算。"
		return []
	if balance < Rules.COST:
		last_error = "金币不足，还需要 %d 金币。" % (Rules.COST - balance)
		return []
	var previous_misses := hidden_misses
	pending = Rules.draw_result(rng, hidden_misses)
	hidden_misses = 0 if Rules.is_hidden(pending) else hidden_misses + 1
	spin_count += 1
	balance -= Rules.COST
	if not persist():
		balance += Rules.COST
		hidden_misses = previous_misses
		spin_count -= 1
		pending = []
		return []
	balance_changed.emit(balance)
	return pending.duplicate()

func settle_spin() -> int:
	if pending.is_empty():
		return -1
	var symbols := pending.duplicate()
	var reward := Rules.payout(symbols)
	var record: Dictionary = {}
	if Rules.is_hidden(symbols):
		record = {"id": "slot-hidden-%d" % spin_count, "spin": spin_count,
			"pool_id": "limited_slot_prize", "reward_id": null, "status": "reserved"}
		hidden_prizes.append(record)
	balance += reward
	pending = []
	if not persist():
		balance -= reward
		pending = symbols
		if not record.is_empty():
			hidden_prizes.pop_back()
		return -1
	balance_changed.emit(balance)
	if not record.is_empty():
		hidden_prize_reserved.emit(record.duplicate(true))
	return reward

func get_reserved_hidden_prizes() -> Array:
	# Stable record IDs let a future inventory service process each award once.
	return hidden_prizes.duplicate(true)

func _whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum and value == floor(value)

func _valid_hidden_data(data: Dictionary) -> bool:
	if not _whole_number(data.get("hidden_misses"), 0, Rules.HIDDEN_PITY - 1):
		return false
	if not _whole_number(data.get("spin_count"), 0, 1000000000000) or not data.get("hidden_prizes") is Array:
		return false
	if data.hidden_misses > data.spin_count:
		return false
	var ids: Dictionary = {}
	for record in data.hidden_prizes:
		if not record is Dictionary or not _whole_number(record.get("spin"), 1, int(data.spin_count)):
			return false
		var expected_id := "slot-hidden-%d" % int(record.spin)
		if record.get("id") != expected_id or ids.has(expected_id):
			return false
		if record.get("pool_id") != "limited_slot_prize" or record.get("status") != "reserved" or record.get("reward_id") != null:
			return false
		ids[expected_id] = true
	if Rules.is_hidden(data.pending):
		if data.hidden_misses != 0 or data.spin_count < 1 or ids.has("slot-hidden-%d" % int(data.spin_count)):
			return false
	return true
