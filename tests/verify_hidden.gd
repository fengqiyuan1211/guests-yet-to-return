extends Node
const Rules := preload("res://scripts/slot_rules.gd")
const Wallet := preload("res://scripts/slot_wallet.gd")
var failures: Array[String] = []
var notices := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _ready() -> void:
	if not SlotWallet.save_path.begins_with("/tmp/"):
		get_tree().quit(1)
		return
	var w := Wallet.new()
	w.save_path = "/tmp/hidden-prize-unit-wallet.json"
	w.balance = 10000
	w.hidden_prize_reserved.connect(func(_record): notices += 1)
	var probe := RandomNumberGenerator.new()
	var hit_seed := -1
	var miss_seed := -1
	for seed_value in range(10000):
		probe.seed = seed_value
		if Rules.is_hidden(Rules.draw_result(probe, 0)):
			hit_seed = seed_value
		else:
			miss_seed = seed_value
		if hit_seed >= 0 and miss_seed >= 0:
			break
	check(hit_seed >= 0 and miss_seed >= 0, "Find deterministic hit and miss")
	check(Rules.HIDDEN_CHANCE_DENOMINATOR == 200, "Latest chance must be 0.5 percent")
	probe.seed = 876541
	var hits := 0
	for i in range(100000):
		if Rules.is_hidden(Rules.draw_result(probe, 0)):
			hits += 1
	check(absf(hits / 100000.0 - 0.005) < 0.001, "Natural chance sanity check")
	check(not Rules.valid_result([5,1,1]), "Gold cannot appear as a mixed result")
	check(Rules.payout([5,5,5]) == 0, "No invented reward")
	for i in range(99):
		w.rng.seed = miss_seed
		check(not Rules.is_hidden(w.begin_spin()), "No premature pity")
		check(w.hidden_misses == i + 1, "Every paid miss advances pity once")
		var charged := w.balance
		check(w.begin_spin().is_empty() and w.balance == charged and w.hidden_misses == i + 1, "Duplicate input cannot advance pity")
		w.settle_spin()
	w.load_wallet()
	check(w.hidden_misses == 99, "Restart preserves 99 misses")
	var funds := w.balance
	w.balance = 19
	check(w.begin_spin().is_empty() and w.hidden_misses == 99, "Insufficient funds cannot consume pity")
	w.balance = funds
	var original_path := w.save_path
	w.save_path = "/tmp/slot-nonexistent-%d/wallet.json" % Time.get_ticks_usec()
	check(w.begin_spin().is_empty() and w.hidden_misses == 99 and w.spin_count == 99 and w.balance == funds, "Failed save rolls back stake and pity")
	w.save_path = original_path
	w.rng.seed = miss_seed
	check(w.begin_spin() == [5,5,5] and w.hidden_misses == 0, "Spin 100 is guaranteed despite miss RNG")
	check(w.hidden_prizes.is_empty(), "Prize waits for settlement")
	w.save_path = "/tmp/slot-nonexistent-%d/wallet.json" % Time.get_ticks_usec()
	check(w.settle_spin() == -1 and w.hidden_prizes.is_empty() and w.pending == [5,5,5] and notices == 0, "Failed settlement cannot issue prize")
	w.save_path = original_path
	w.load_wallet()
	check(w.recovered_hidden and w.hidden_prizes.size() == 1 and notices == 1, "Interrupted gold spin recovers exactly one prize")
	check(w.hidden_prizes[0].reward_id == null and w.hidden_prizes[0].status == "reserved", "Reward remains unassigned")
	check(w.balance == funds - 20, "Hidden event pays zero coins for now")
	w.load_wallet()
	check(w.hidden_prizes.size() == 1 and notices == 1 and w.settle_spin() == -1, "Repeated reload or settle cannot duplicate reward")
	w.hidden_misses = 37
	w.rng.seed = hit_seed
	check(w.begin_spin() == [5,5,5] and w.hidden_misses == 0, "Natural hit resets pity early")
	w.settle_spin()
	check(w.hidden_prizes.size() == 2 and w.hidden_prizes[0].id != w.hidden_prizes[1].id, "Distinct wins have stable distinct IDs")
	var records := w.get_reserved_hidden_prizes()
	records[0].status = "changed"
	check(w.hidden_prizes[0].status == "reserved", "Future integration receives immutable snapshot")
	w.rng.seed = miss_seed
	w.begin_spin()
	check(w.hidden_misses == 1, "Pity starts at one on next miss")
	w.settle_spin()
	var legacy := FileAccess.open(original_path, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"version":1,"balance":280,"pending":[0,0,0]}))
	legacy.close()
	w.load_wallet()
	check(w.balance == 2280 and w.hidden_misses == 0 and w.hidden_prizes.is_empty(), "Legacy wallet migrates and preserves pending reward")
	w.free()
	print("HIDDEN PRIZE VERIFICATION: ", "PASS" if failures.is_empty() else "FAIL", " | natural hits/100000=", hits, " | pity, migration, rollback, recovery, reserved awards")
	get_tree().quit(0 if failures.is_empty() else 1)
