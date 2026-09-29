extends Node
const Rules := preload("res://scripts/slot_rules.gd")
var failures: Array[String] = []
var home: Control
var capture := false

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	capture = "--screenshots" in OS.get_cmdline_user_args()
	call_deferred("run")

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func screenshot(file: String) -> void:
	if not capture or DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../output/slot-preview")
	DirAccess.make_dir_recursive_absolute(folder)
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(file)) == OK, "Screenshot failed")

func click(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_rect().get_center()
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)

func run() -> void:
	# Fail closed rather than ever altering the player's wallet during testing.
	if not SlotWallet.save_path.begins_with("/tmp/"):
		push_error("Use -- --slot-wallet=/tmp/<test-wallet>.json")
		get_tree().quit(1)
		return
	check(absf(Rules.expected_payout() - 16.92703) < 0.000001, "Expected payout must match exhaustive enumeration")
	check(Rules.expected_payout() < Rules.COST, "Expected net return must be negative")
	for i in range(5):
		check(Rules.payout([i,i,i]) == Rules.TRIPLES[i], "Triple payout mismatch")
		for other in range(5):
			if other == i:
				continue
			for symbols in [[i, i, other], [i, other, i], [other, i, i]]:
				check(Rules.payout(symbols) == Rules.PAIRS[i], "Pair position should not matter")
	check(Rules.payout([0,1,2]) == 0, "Different symbols should not pay")
	SlotWallet.balance = 300
	SlotWallet.pending = []
	SlotWallet.hidden_misses = 0
	SlotWallet.spin_count = 0
	SlotWallet.hidden_prizes = []
	check(SlotWallet.persist(), "Test wallet must be writable")
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	await screenshot("01-home-entry.png")
	click(home.get_node("%SlotsButton"))
	await settle()
	check(Navigation.current_route == &"slots", "Top right icon should open machine")
	var page = home.active_page
	await screenshot("02-machine-ready.png")
	click(page.help_button)
	await settle()
	check(page.rules_overlay.visible, "Question mark opens award paper")
	await screenshot("07-awards-paper.png")
	page.start_spin()
	check(SlotWallet.balance == 300 and not page.busy, "Award paper blocks spins behind it")
	click(page.lever)
	check(SlotWallet.balance == 300 and not page.busy, "Outside click must not pass through to lever")
	click(page.help_button)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	await settle()
	check(Navigation.current_route == &"slots" and not page.rules_overlay.visible, "Escape closes paper before machine")
	click(page.help_button)
	await settle()
	click(page.rules_close)
	check(not page.rules_overlay.visible, "Paper close button works")
	click(page.lever)
	await settle()
	check(page.busy, "Native lever click must begin spin")
	check(SlotWallet.balance == 280, "Deduct exactly one stake immediately")
	var expected_reward := Rules.payout(SlotWallet.pending)
	page.start_spin()
	Navigation.go_to(&"home")
	check(SlotWallet.balance == 280, "Repeated input must not deduct twice")
	check(Navigation.current_route == &"slots", "Navigation must wait for settlement")
	await get_tree().create_timer(0.13).timeout
	check(page.lever.pull > 0, "Lever must physically move downward")
	await screenshot("03-lever-pulled.png")
	click(page.help_button)
	check(page.rules_overlay.visible, "Award paper can be read during spin")
	var deadline := Time.get_ticks_msec() + 9000
	while page.busy and Time.get_ticks_msec() < deadline:
		check(SlotWallet.balance == 280, "No payout before all reels finish")
		await get_tree().process_frame
	check(not page.busy, "Spin must finish")
	check(page.stops == [0,1,2], "Reels must stop left to right")
	check(SlotWallet.balance == 280 + expected_reward, "Correct final balance")
	check(SlotWallet.pending.is_empty(), "Settlement clears pending transaction")
	check(SlotWallet.settle_spin() == -1, "Transaction cannot be settled twice")
	check(home.get_node("%GoldValue").text == str(SlotWallet.balance), "Home balance must synchronize")
	check(get_viewport().gui_get_focus_owner() == page.rules_close, "Settlement preserves award paper focus")
	click(page.rules_close)
	await screenshot("04-settled.png")
	# Find a real RNG seed for the rare jackpot; production has no forced-win path.
	var probe := RandomNumberGenerator.new()
	var jackpot_seed := -1
	for seed_value in range(300000):
		probe.seed = seed_value
		if Rules.draw_result(probe, 0) == [0,0,0]:
			jackpot_seed = seed_value
			break
	check(jackpot_seed >= 0, "Find reproducible jackpot test seed")
	SlotWallet.rng.seed = jackpot_seed
	var previous_balance: int = SlotWallet.balance
	page.start_spin()
	check(SlotWallet.pending == [0,0,0], "Jackpot symbols must be three fa")
	deadline = Time.get_ticks_msec() + 9000
	while page.busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(SlotWallet.balance == previous_balance - 20 + 2000, "Jackpot pays 2000 gross")
	await screenshot("05-jackpot.png")
	# Exercise pity through the real UI using only the isolated test wallet.
	SlotWallet.hidden_misses = 99
	SlotWallet.spin_count = maxi(SlotWallet.spin_count, 99)
	var before_hidden := SlotWallet.hidden_prizes.size()
	previous_balance = SlotWallet.balance
	click(page.lever)
	check(SlotWallet.pending == [5,5,5], "Hidden result must be three gold icons")
	check(SlotWallet.hidden_prizes.size() == before_hidden, "Do not reserve prize before reels stop")
	deadline = Time.get_ticks_msec() + 9000
	while page.busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(page.stops == [0,1,2], "Hidden reels stop in order")
	check(page.status.text == "恭喜你，触发隐藏大奖！", "Hidden award must not show losing copy")
	check(SlotWallet.hidden_prizes.size() == before_hidden + 1, "Persist one reserved prize")
	check(SlotWallet.balance == previous_balance - 20, "Hidden prize has no placeholder coin payout")
	check(SlotWallet.hidden_misses == 0, "Hidden prize resets pity")
	await screenshot("08-hidden-jackpot.png")
	# Gold must not remain in a subsequent ordinary reel strip.
	for reel in page.reels:
		reel.spin_to(1, 0)
		check(not reel.strip.has(5), "Old hidden icon must not flash on ordinary spins")
		if reel.motion:
			reel.motion.kill()
	page.request_close()
	await settle()
	check(Navigation.current_route == &"home", "Return to home after settlement")
	# Reopen after resizing to a long phone landscape viewport.
	get_window().size = Vector2i(1280, 576)
	await settle()
	click(home.get_node("%SlotsButton"))
	await settle()
	check(Navigation.current_route == &"slots", "Reopen at phone aspect ratio")
	await screenshot("06-phone-layout.png")
	Navigation.go_to(&"home")
	await settle()
	# Insufficient funds and restart recovery use this isolated wallet only.
	SlotWallet.balance = 19
	check(SlotWallet.begin_spin().is_empty(), "Insufficient balance must not spin")
	check(SlotWallet.balance == 19, "Insufficient balance must not be deducted")
	SlotWallet.balance = 300
	SlotWallet.rng.seed = jackpot_seed
	SlotWallet.begin_spin()
	check(SlotWallet.balance == 280, "Interrupted spin is paid upfront")
	SlotWallet.load_wallet()
	check(SlotWallet.balance == 2280 and SlotWallet.pending.is_empty(), "Restart recovers pending jackpot")
	SlotWallet.load_wallet()
	check(SlotWallet.balance == 2280, "Repeated load does not duplicate reward")
	print("SLOTS VERIFICATION: ", "PASS" if failures.is_empty() else "FAIL", " | expected payout=", Rules.expected_payout(), " | UI, ordered stops, payout timing, double input, jackpot, save/recovery")
	get_tree().quit(0 if failures.is_empty() else 1)
